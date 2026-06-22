#requires -Version 5.1
<#
.SYNOPSIS
  Sync data from REMOTE Supabase (cloud) -> LOCAL Supabase (Docker) on this machine.

.DESCRIPTION
  Steps:
    1. Dump data-only from remote into Backend/supabase/seed.sql (overwrites)
    2. Save a timestamped backup copy to Backend/backups/seed-YYYYMMDD-HHMMSS.sql
    3. Prune Backend/backups/ to keep only the N most recent backups
    4. If local Docker container is running, truncate `contactForm` and re-apply seed
    5. Log everything to Backend/backups/sync.log

  Designed to be run manually OR by Windows Task Scheduler.

.PARAMETER MaxBackups
  Number of timestamped backup files to keep. Older ones are auto-deleted. Default: 15.

.PARAMETER SkipLocalApply
  Only dump from remote and save snapshot; do NOT touch the local DB.

.EXAMPLE
  .\sync-from-remote.ps1
  .\sync-from-remote.ps1 -MaxBackups 30
  .\sync-from-remote.ps1 -SkipLocalApply
#>
param(
  [int]$MaxBackups = 15,
  [switch]$SkipLocalApply
)

$ErrorActionPreference = "Stop"

$BackendDir   = Split-Path -Parent $PSScriptRoot
$ProjectRoot  = Split-Path -Parent $BackendDir
$BackupsDir   = Join-Path $BackendDir "backups"
$LogsDir      = Join-Path $BackendDir "logs"
$SeedFile     = Join-Path $BackendDir "supabase\seed.sql"
$LogFile      = Join-Path $LogsDir "sync.log"
$ContainerName = "supabase_db_tule-website"

if (-not (Test-Path $BackupsDir)) {
  New-Item -ItemType Directory -Path $BackupsDir -Force | Out-Null
}
if (-not (Test-Path $LogsDir)) {
  New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

function Write-Log {
  param([string]$Level, [string]$Message)
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts] [$Level] $Message"
  $line | Tee-Object -FilePath $LogFile -Append | Out-Null
  Write-Host $line
}

Write-Log "INFO" "===== Sync run started ====="
Write-Log "INFO" "Backend dir: $BackendDir"
Write-Log "INFO" "Max backups to keep: $MaxBackups"

try {
  Push-Location $BackendDir

  Write-Log "INFO" "Step 1/5: Dumping data from remote Supabase..."
  $dumpOutput = cmd /c "npx --yes supabase db dump --data-only --linked -f supabase\seed.sql 2>&1"
  if ($LASTEXITCODE -ne 0) {
    throw "Remote dump failed (exit $LASTEXITCODE): $dumpOutput"
  }
  Write-Log "INFO" "Remote dump OK. seed.sql size: $((Get-Item $SeedFile).Length) bytes"

  Write-Log "INFO" "Step 2/5: Saving timestamped backup..."
  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $backupFile = Join-Path $BackupsDir "seed-$stamp.sql"
  Copy-Item -Path $SeedFile -Destination $backupFile -Force
  Write-Log "INFO" "Snapshot saved: $backupFile"

  Write-Log "INFO" "Step 3/5: Pruning old backups (keep $MaxBackups)..."
  $all = Get-ChildItem -Path $BackupsDir -Filter "seed-*.sql" | Sort-Object LastWriteTime -Descending
  if ($all.Count -gt $MaxBackups) {
    $toDelete = $all | Select-Object -Skip $MaxBackups
    foreach ($f in $toDelete) {
      Remove-Item -Path $f.FullName -Force
      Write-Log "INFO" "Deleted old backup: $($f.Name)"
    }
  } else {
    Write-Log "INFO" "Backup count: $($all.Count) (under limit, no pruning)"
  }

  if ($SkipLocalApply) {
    Write-Log "INFO" "Step 4/5: SKIPPED (--SkipLocalApply flag set)"
  } else {
    Write-Log "INFO" "Step 4/5: Applying seed to local Docker container..."
    $running = & docker ps --filter "name=$ContainerName" --format "{{.Names}}" 2>$null
    if (-not $running) {
      Write-Log "WARN" "Container '$ContainerName' is NOT running. Skipping local apply."
      Write-Log "WARN" "(Tip: 'npx supabase start' from Backend/ to bring it up, then rerun this script.)"
    } else {
      Write-Log "INFO" "Container is up. Building combined truncate+seed file..."
      $combined = Join-Path $env:TEMP "tule-seed-apply.sql"
      $truncateLine = 'TRUNCATE TABLE public."contactForm" RESTART IDENTITY CASCADE;'
      $seedBody = Get-Content -Path $SeedFile -Raw
      ($truncateLine + "`n" + $seedBody) | Set-Content -Path $combined -Encoding UTF8 -NoNewline

      Write-Log "INFO" "Copying combined SQL into container..."
      & docker cp $combined "${ContainerName}:/tmp/seed-apply.sql" 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "docker cp failed" }

      Write-Log "INFO" "Applying combined SQL via psql..."
      $applyOut = & docker exec $ContainerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/seed-apply.sql 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "Apply failed: $applyOut"
      }

      Remove-Item -Path $combined -Force -ErrorAction SilentlyContinue

      $rowCountSql = Join-Path $env:TEMP "tule-rowcount.sql"
      'select count(*) from public."contactForm";' | Set-Content -Path $rowCountSql -Encoding UTF8 -NoNewline
      & docker cp $rowCountSql "${ContainerName}:/tmp/rowcount.sql" 2>&1 | Out-Null
      $rowCountOut = & docker exec $ContainerName psql -U postgres -d postgres -tA -f /tmp/rowcount.sql 2>&1
      Remove-Item -Path $rowCountSql -Force -ErrorAction SilentlyContinue
      Write-Log "INFO" "Local contactForm now has $(($rowCountOut | Out-String).Trim()) row(s)."
    }
  }

  Write-Log "INFO" "Step 5/5: Generating human-readable view..."
  $viewScript = Join-Path $PSScriptRoot "generate-readable-view.ps1"
  if (Test-Path $viewScript) {
    $viewOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $viewScript 2>&1
    if ($LASTEXITCODE -eq 0) {
      Write-Log "INFO" ($viewOut | Out-String).Trim()
    } else {
      Write-Log "WARN" "View generator failed: $($viewOut | Out-String)"
    }
  } else {
    Write-Log "WARN" "generate-readable-view.ps1 not found at $viewScript"
  }

  Write-Log "INFO" "===== Sync run finished OK ====="
  exit 0
}
catch {
  Write-Log "ERROR" $_.Exception.Message
  Write-Log "ERROR" "===== Sync run FAILED ====="
  exit 1
}
finally {
  Pop-Location
}

#requires -Version 5.1
<#
.SYNOPSIS
  Parse the latest seed-*.sql backup and render contactForm rows as a Markdown table.

.DESCRIPTION
  Reads the most recent Backend/backups/seed-*.sql file (or one specified via -SqlFile),
  extracts INSERT INTO "public"."contactForm" rows, and writes a human-readable
  Markdown table to Backend/contact-submissions.md (overwriting it).

  Called automatically by sync-from-remote.ps1 after each successful sync, but can
  also be run manually.

.PARAMETER SqlFile
  Path to a specific seed-*.sql file. If omitted, picks the most recent in Backend/backups/.

.PARAMETER OutputFile
  Path to the markdown file to write. Default: Backend/contact-submissions.md.

.EXAMPLE
  .\generate-readable-view.ps1
  .\generate-readable-view.ps1 -SqlFile "C:\path\to\specific.sql"
#>
param(
  [string]$SqlFile,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"

$BackendDir = Split-Path -Parent $PSScriptRoot
$BackupsDir = Join-Path $BackendDir "backups"

if (-not $SqlFile) {
  $latest = Get-ChildItem -Path $BackupsDir -Filter "seed-*.sql" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) {
    Write-Error "No seed-*.sql files found in $BackupsDir. Run sync-from-remote.ps1 first."
    exit 1
  }
  $SqlFile = $latest.FullName
}

if (-not (Test-Path $SqlFile)) {
  Write-Error "SQL file not found: $SqlFile"
  exit 1
}

if (-not $OutputFile) {
  $OutputFile = Join-Path $BackendDir "contact-submissions.md"
}

Write-Host "Parsing: $SqlFile"

$sqlContent = Get-Content -Path $SqlFile -Raw

# Locate the INSERT INTO "public"."contactForm" ... VALUES block and capture
# everything up to the terminating semicolon.
$blockPattern = '(?s)INSERT INTO\s+"public"\."contactForm"[^;]*VALUES\s*(.+?);'
$blockMatch = [regex]::Match($sqlContent, $blockPattern)

$rows = @()

if ($blockMatch.Success) {
  $valuesBlob = $blockMatch.Groups[1].Value

  # Each row tuple: (int, 'ts', 'name', 'email', 'message')
  # Strings use SQL escaping: '' represents a single quote inside the literal.
  $rowPattern = "(?s)\(\s*(\d+)\s*,\s*'((?:[^']|'')*)'\s*,\s*'((?:[^']|'')*)'\s*,\s*'((?:[^']|'')*)'\s*,\s*'((?:[^']|'')*)'\s*\)"
  $rowMatches = [regex]::Matches($valuesBlob, $rowPattern)

  foreach ($m in $rowMatches) {
    $rows += [pscustomobject]@{
      Id        = [int]$m.Groups[1].Value
      CreatedAt = $m.Groups[2].Value
      Name      = $m.Groups[3].Value -replace "''", "'"
      Email     = $m.Groups[4].Value -replace "''", "'"
      Message   = $m.Groups[5].Value -replace "''", "'"
    }
  }
}

# Markdown-safe cell escaping: backslash-escape pipe, replace newlines with <br>.
function Format-Cell {
  param([string]$Value)
  if ($null -eq $Value) { return "" }
  $v = $Value -replace '\|', '\|'
  $v = $v -replace "`r`n", "<br>"
  $v = $v -replace "`n",   "<br>"
  $v = $v -replace "`r",   "<br>"
  return $v
}

# Convert "2026-06-19 04:30:20.001756+00" to "2026-06-19 04:30 UTC" for readability.
function Format-Timestamp {
  param([string]$RawTs)
  try {
    $dt = [datetime]::Parse($RawTs, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    return $dt.ToString("yyyy-MM-dd HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture)
  } catch {
    return $RawTs
  }
}

$now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
$sourceName = Split-Path -Leaf $SqlFile

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Contact Submissions")
[void]$md.AppendLine()
[void]$md.AppendLine("_Last updated: **$now**_  ")
[void]$md.AppendLine("_Source: ``$sourceName``_  ")
[void]$md.AppendLine("_Total: **$($rows.Count)** submission(s)_")
[void]$md.AppendLine()

if ($rows.Count -eq 0) {
  [void]$md.AppendLine("> No contact form submissions yet.")
} else {
  [void]$md.AppendLine("| # | Submitted | Name | Email | Message |")
  [void]$md.AppendLine("|---|-----------|------|-------|---------|")
  foreach ($r in ($rows | Sort-Object Id)) {
    $ts    = Format-Cell (Format-Timestamp $r.CreatedAt)
    $name  = Format-Cell $r.Name
    $email = Format-Cell $r.Email
    $msg   = Format-Cell $r.Message
    [void]$md.AppendLine("| $($r.Id) | $ts | $name | $email | $msg |")
  }
}

Set-Content -Path $OutputFile -Value $md.ToString() -Encoding UTF8 -NoNewline
Write-Host "Wrote: $OutputFile  ($($rows.Count) rows)"

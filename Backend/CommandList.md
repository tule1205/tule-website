# Run sync now 
Start-ScheduledTask -TaskName "TuleWebsiteSupabaseSync"

# See task's status
Get-ScheduledTaskInfo -TaskName "TuleWebsiteSupabaseSync"

# See nearest logs
Get-Content C:\MyProjects\tule-website\Backend\backups\sync.log -Tail 20

# See backup lists
ls C:\MyProjects\tule-website\Backend\backups\seed-*.sql

# Run script manual with option 
powershell -File C:\MyProjects\tule-website\Backend\scripts\sync-from-remote.ps1 -SkipLocalApply

# Change amount of backup files
powershell -File C:\MyProjects\tule-website\Backend\scripts\sync-from-remote.ps1 -MaxBackups 30

# Turn off scheduled task
Disable-ScheduledTask -TaskName "TuleWebsiteSupabaseSync"
Enable-ScheduledTask -TaskName "TuleWebsiteSupabaseSync"

# Delete scheduled task
Unregister-ScheduledTask -TaskName "TuleWebsiteSupabaseSync" -Confirm:$false

# Open Task Scheduler GUI to inspect/edit the task
# 1. Hit Windows key + R
# 2. Type taskschd.msc -> Enter
# 3. Task Scheduler opens
# 4. Find TuLeWebsiteSupabaseSync
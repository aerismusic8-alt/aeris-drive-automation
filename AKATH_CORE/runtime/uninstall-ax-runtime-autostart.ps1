$ErrorActionPreference = 'Stop'
$TaskName = 'AERIS-AKATH-AX-RUNTIME'

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Write-Output "Removed scheduled task: $TaskName"
} else {
  Write-Output "Scheduled task not present: $TaskName"
}

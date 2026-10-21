# PC1 reverse-channel watchdog: decide when the channel is unhealthy and repair it.
#
# The channel is a poll loop on PC1 that dequeues jobs from the agent's
# rendezvous and runs them. Nothing else notices when that loop stops turning.
# On 2026-10-21 jobs 67 and 68 were dequeued and never answered: the worker was
# wedged inside a tool call, so it took the job and stopped polling. The agent
# saw a silent queue and had no way to tell "busy" from "dead". The fix has two
# halves, and this file is the second:
#
#   1. The worker writes a heartbeat file every cycle (ax-pc1-worker.py).
#   2. This watchdog reads that file and decides from the heartbeat's age.
#
# The thresholds are the answer to "how long is abnormal":
#
#   * Under $HealthySeconds the loop is working. A poll plus a normal tool call
#     is a few seconds; a screen capture or a shell command can take ten.
#   * At $HealthySeconds the loop is stale. Nothing legitimate holds the loop
#     that long, because the worker abandons a tool call at its own job timeout
#     (120s by default). Stale means: restart the task.
#   * With no heartbeat file at all the channel never started, so start it.
#
# Repair is restarting the scheduled task, which the task's own RestartCount
# also does for a crash. This covers the case the task settings cannot see: a
# process that is alive but no longer making progress.

param(
  [string]$RuntimeRoot = 'C:\AX-Runtime',
  [string]$TaskName = 'AERIS-PC1-REVERSE-CONTROL',
  [int]$HealthySeconds = 180,
  [int]$MarginSeconds = 60,
  [int]$PollSeconds = 30,
  [switch]$SelfTest,
  [switch]$Once
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$evidenceDir = Join-Path $RuntimeRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$heartbeatPath = Join-Path $evidenceDir 'reverse-control-heartbeat.json'
$watchdogPath = Join-Path $evidenceDir 'reverse-control-watchdog-heartbeat.json'
$logPath = Join-Path $evidenceDir 'reverse-control-watchdog.log'

function Write-Log([string]$Line) {
  $stamp = (Get-Date).ToUniversalTime().ToString('o')
  "$stamp $Line" | Add-Content -LiteralPath $logPath -Encoding UTF8
  Write-Host $Line
}

function Get-Heartbeat {
  # Returns the parsed heartbeat, or $null when there is no readable one.
  # A half-written file is possible: the worker truncates then writes, so a read
  # that lands between those two steps sees invalid JSON. That is not a failure,
  # it is a race, and the next poll a second later sees the finished file.
  if (-not (Test-Path -LiteralPath $heartbeatPath)) { return $null }
  try {
    $raw = Get-Content -LiteralPath $heartbeatPath -Raw -ErrorAction Stop
    return $raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return $null
  }
}

function Get-HeartbeatAge {
  param($Heartbeat)
  if ($null -eq $Heartbeat) { return $null }
  try {
    $at = [DateTime]::Parse($Heartbeat.heartbeatAt, [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
    return [math]::Round(([DateTime]::UtcNow - $at).TotalSeconds, 1)
  } catch {
    return $null
  }
}

function Get-EffectiveThreshold {
  # The worker publishes how long one tool call may run. The heartbeat is only
  # rewritten between jobs, so a healthy worker inside a slow call is silent for
  # up to that long. The threshold is therefore the job cap plus a margin for the
  # poll and the write, not a number picked independently: if the two disagree,
  # a legitimate long job reads as a dead channel and gets restarted mid-call.
  # $HealthySeconds is the floor, used when the worker publishes nothing.
  param($Heartbeat, [int]$Floor)
  $cap = 0
  if ($Heartbeat -and $Heartbeat.jobTimeout) {
    $cap = [int][double]$Heartbeat.jobTimeout
  }
  $derived = $cap + $MarginSeconds
  if ($derived -gt $Floor) { return $derived }
  return $Floor
}

function Get-ChannelDecision {
  # Pure decision, so it can be tested without Windows: given the heartbeat age
  # and the threshold, name the health. Kept separate from the repair so a test
  # asserts the rule rather than the side effects.
  param($AgeSeconds, [int]$Healthy)
  if ($null -eq $AgeSeconds) { return 'missing' }
  if ($AgeSeconds -gt $Healthy) { return 'stale' }
  return 'ok'
}

function Invoke-SelfTest {
  # The decision table, checked on the machine it runs on. The cases are the
  # boundaries that matter: fresh, at the line, past the line, and no heartbeat.
  $cases = @(
    @{ Age = 0;    Healthy = 180; Expect = 'ok' },
    @{ Age = 5;    Healthy = 180; Expect = 'ok' },
    @{ Age = 179;  Healthy = 180; Expect = 'ok' },
    @{ Age = 180;  Healthy = 180; Expect = 'ok' },
    @{ Age = 181;  Healthy = 180; Expect = 'stale' },
    @{ Age = 9999; Healthy = 180; Expect = 'stale' },
    @{ Age = $null; Healthy = 180; Expect = 'missing' }
  )
  $failed = 0
  foreach ($c in $cases) {
    $got = Get-ChannelDecision -AgeSeconds $c.Age -Healthy $c.Healthy
    if ($got -ne $c.Expect) {
      $failed++
      Write-Host "SELFTEST_FAIL age=$($c.Age) expected=$($c.Expect) got=$got"
    } else {
      Write-Host "SELFTEST_OK age=$($c.Age) expected=$($c.Expect) got=$got"
    }
  }

  # The threshold rule. A worker that publishes a 120s job cap must not be called
  # stale at 121s: it may be inside a legitimate call. It must be called stale
  # once the cap plus the margin has passed with no heartbeat.
  $thresholdCases = @(
    @{ Name = 'publishes 120s cap'; Cap = 120; Floor = 180; Expect = 180 },
    @{ Name = 'publishes 600s cap'; Cap = 600; Floor = 180; Expect = 660 },
    @{ Name = 'publishes nothing'; Cap = $null; Floor = 180; Expect = 180 }
  )
  foreach ($c in $thresholdCases) {
    $hb = if ($null -eq $c.Cap) { [pscustomobject]@{} } else { [pscustomobject]@{ jobTimeout = $c.Cap } }
    $got = Get-EffectiveThreshold -Heartbeat $hb -Floor $c.Floor
    if ($got -ne $c.Expect) {
      $failed++
      Write-Host "SELFTEST_FAIL $($c.Name) expected=$($c.Expect) got=$got"
    } else {
      Write-Host "SELFTEST_OK $($c.Name) threshold=$got"
    }
  }

  # The case that would have caused a false restart: a long-but-healthy job.
  $longJobAge = 121
  $threshold = Get-EffectiveThreshold -Heartbeat ([pscustomobject]@{ jobTimeout = 120 }) -Floor 180
  $health = Get-ChannelDecision -AgeSeconds $longJobAge -Healthy $threshold
  if ($health -ne 'ok') {
    $failed++
    Write-Host "SELFTEST_FAIL long healthy job at ${longJobAge}s read as $health"
  } else {
    Write-Host "SELFTEST_OK long healthy job at ${longJobAge}s reads ok (threshold=$threshold)"
  }

  if ($failed -gt 0) { Write-Host "SELFTEST_RESULT=FAIL failed=$failed"; exit 1 }
  Write-Host 'SELFTEST_RESULT=PASS'
  exit 0
}

function Invoke-ChannelRepair {
  param([string]$Health, $AgeSeconds, $Actions)
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if (-not $task) {
    $Actions.Add('TASK_MISSING')
    Write-Log "TASK_MISSING: $TaskName is not registered"
    return
  }
  if ($Health -eq 'ok') { return }
  try {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName $TaskName
    $Actions.Add("RESTARTED:${TaskName}:$Health")
    Write-Log "RESTARTED:${TaskName} health=$Health age=$AgeSeconds"
  } catch {
    $Actions.Add("RESTART_FAILED:${TaskName}:$($_.Exception.Message)")
    Write-Log "RESTART_FAILED:${TaskName}:$($_.Exception.Message)"
  }
}

if ($SelfTest) { Invoke-SelfTest }

while ($true) {
  $actions = New-Object System.Collections.Generic.List[string]
  $hb = Get-Heartbeat
  $age = Get-HeartbeatAge -Heartbeat $hb
  $threshold = Get-EffectiveThreshold -Heartbeat $hb -Floor $HealthySeconds
  $health = Get-ChannelDecision -AgeSeconds $age -Healthy $threshold
  Invoke-ChannelRepair -Health $health -AgeSeconds $age -Actions $actions

  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  $report = [ordered]@{
    protocol     = 'AX PC1 REVERSE CONTROL WATCHDOG v1'
    nodeId       = 'PC1'
    computerName = $env:COMPUTERNAME
    status       = 'ALIVE'
    heartbeatAt  = (Get-Date).ToUniversalTime().ToString('o')
    channelHealth = $health
    heartbeatAgeSeconds = $age
    healthySeconds = $threshold
    healthyFloor = $HealthySeconds
    workerJobTimeout = if ($hb) { $hb.jobTimeout } else { $null }
    workerState  = if ($hb) { $hb.state } else { $null }
    workerJobId  = if ($hb) { $hb.jobId } else { $null }
    taskName     = $TaskName
    taskState    = if ($task) { [string]$task.State } else { 'MISSING' }
    actions      = @($actions)
  }
  Set-Content -LiteralPath $watchdogPath -Value ($report | ConvertTo-Json -Depth 6) -Encoding UTF8

  Write-Host "CHANNEL_HEALTH=$health AGE=$age THRESHOLD=$threshold TASK=$(if ($task) { $task.State } else { 'MISSING' })"
  Write-Host "ACTIONS=$(if ($actions.Count -gt 0) { $actions -join ',' } else { 'none' })"

  if ($Once) { Write-Host 'WATCHDOG=ONCE'; break }
  Start-Sleep -Seconds $PollSeconds
}

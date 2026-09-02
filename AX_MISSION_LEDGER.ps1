$ErrorActionPreference = 'Stop'

$script:AxMissionStatuses = @('CREATED','FEASIBILITY','APPROVED','DISPATCHED','EXECUTING','OUTPUT','VERIFYING','EVIDENCE','AX_CERTIFIED','DELIVERED','BUSINESS_EXTENSION','FAILED','NEEDS_REWORK','BLOCKED','ARCHIVED')
$script:AxSecretNames = @('token','password','apikey','api_key','authorization','secret','client_secret','private_key')

function Get-AxValue($Object, [string]$Name, $Default = $null) {
  if ($null -eq $Object) { return $Default }
  $p = $Object.PSObject.Properties[$Name]
  if ($null -eq $p) { return $Default }
  return $p.Value
}

function ConvertTo-AxIsoTime([object]$Value) {
  if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o') }
  try { return ([datetime]::Parse([string]$Value)).ToUniversalTime().ToString('o') } catch { return (Get-Date).ToUniversalTime().ToString('o') }
}

function Get-AxSha256([string]$Text) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}

function New-AxEventId {
  param([string]$MissionId,[string]$Timestamp,[string]$Channel,[string]$EventType,[string]$Content,[string]$SourceId)
  Get-AxSha256 ("$MissionId|$Timestamp|$Channel|$EventType|$SourceId|$Content")
}

function New-AxMissionId {
  param([string]$Objective,[string]$CreatedAt,[string]$SourceId)
  'AXM-' + (Get-AxSha256 ("$CreatedAt|$SourceId|$Objective").Substring(0,20).ToUpperInvariant())
}

function Protect-AxSecretText([string]$Text) {
  if ($null -eq $Text) { return '' }
  $result = $Text
  foreach ($name in $script:AxSecretNames) {
    $result = [regex]::Replace($result, "(?i)($name)\s*[:=]\s*[^,;\s]+", '$1=[REDACTED]')
  }
  return $result
}

function Normalize-AxMissionEvent {
  param([object]$Event)
  $missionId = [string](Get-AxValue $Event 'missionId' '')
  $timestamp = ConvertTo-AxIsoTime (Get-AxValue $Event 'timestamp' (Get-Date))
  $channel = ([string](Get-AxValue $Event 'channel' 'unknown')).Trim()
  $eventType = ([string](Get-AxValue $Event 'eventType' (Get-AxValue $Event 'type' 'context'))).Trim()
  $content = Protect-AxSecretText ([string](Get-AxValue $Event 'content' (Get-AxValue $Event 'objective' '')))
  $sourceId = [string](Get-AxValue $Event 'sourceId' '')
  if ([string]::IsNullOrWhiteSpace($missionId)) { throw 'AX_MISSION_ID_REQUIRED' }
  $eventId = [string](Get-AxValue $Event 'eventId' '')
  if ([string]::IsNullOrWhiteSpace($eventId)) { $eventId = New-AxEventId $missionId $timestamp $channel $eventType $content $sourceId }
  [ordered]@{
    eventId = $eventId
    missionId = $missionId
    timestamp = $timestamp
    channel = $channel
    eventType = $eventType
    content = $content
    sourceId = $sourceId
    sourceHash = Get-AxSha256 $content
    actor = [string](Get-AxValue $Event 'actor' 'K/AX')
    verified = $true
  }
}

function Upsert-AxMissionEvent {
  param([object]$Ledger,[object]$Event)
  if ($Ledger.schema -ne 'AX_MISSION_LEDGER_V1') { throw 'AX_MISSION_LEDGER_SCHEMA_FAIL' }
  $e = Normalize-AxMissionEvent $Event
  $existing = @($Ledger.events | Where-Object { $_.eventId -eq $e.eventId })
  if ($existing.Count -eq 0) { $Ledger.events = @($Ledger.events) + [pscustomobject]$e }
  $mission = @($Ledger.missions | Where-Object { $_.missionId -eq $e.missionId }) | Select-Object -First 1
  if ($null -eq $mission) {
    $mission = [pscustomobject]@{
      missionId=$e.missionId; createdAt=$e.timestamp; updatedAt=$e.timestamp; objective=$e.content; deadline=$null; priority='NORMAL'; status='CREATED'; channelRefs=@($e.channel); lastConversation=$e.content; workerAllocation=@(); output=$null; verification=$null; evidence=@(); certification=$null; businessExtension=$null; sourceEvents=@($e.eventId)
    }
    $Ledger.missions = @($Ledger.missions) + $mission
  } elseif ($existing.Count -eq 0) {
    $mission.updatedAt=$e.timestamp; $mission.lastConversation=$e.content
    $mission.channelRefs=@(@($mission.channelRefs)+$e.channel | Sort-Object -Unique)
    $mission.sourceEvents=@(@($mission.sourceEvents)+$e.eventId)
  }
  $Ledger.index.missionCount=@($Ledger.missions).Count
  $Ledger.index.eventCount=@($Ledger.events).Count
  $Ledger.index.lastMissionId=$e.missionId
  $Ledger.index.lastEventId=$e.eventId
  return $Ledger
}

function Set-AxMissionStatus {
  param([object]$Ledger,[string]$MissionId,[string]$Status,[string]$Channel='system',[string]$SourceId='status')
  if ($script:AxMissionStatuses -notcontains $Status) { throw "AX_MISSION_STATUS_INVALID:$Status" }
  $mission=@($Ledger.missions | Where-Object missionId -eq $MissionId) | Select-Object -First 1
  if ($null -eq $mission) { throw 'AX_MISSION_NOT_FOUND' }
  $now=(Get-Date).ToUniversalTime().ToString('o')
  $mission.status=$Status; $mission.updatedAt=$now
  $event=[pscustomobject]@{missionId=$MissionId;timestamp=$now;channel=$Channel;eventType='status.change';content="STATUS=$Status";sourceId=$SourceId}
  Upsert-AxMissionEvent $Ledger $event | Out-Null
  return $Ledger
}

function Resolve-AxMission {
  param([object]$Ledger,[string]$MissionId)
  $mission=@($Ledger.missions | Where-Object missionId -eq $MissionId) | Select-Object -First 1
  if ($null -eq $mission) { throw 'AX_MISSION_NOT_FOUND' }
  $events=@($Ledger.events | Where-Object missionId -eq $MissionId | Sort-Object timestamp)
  [pscustomobject]@{ mission=$mission; latestEvent=($events | Select-Object -Last 1); latestConversation=$mission.lastConversation; eventHistory=$events }
}

function Get-AxMissionSummary { param([object]$Ledger) [pscustomobject]@{ schema=$Ledger.schema; missionCount=@($Ledger.missions).Count; eventCount=@($Ledger.events).Count; active=@($Ledger.missions | Where-Object { $_.status -notin @('DELIVERED','ARCHIVED','FAILED') }).Count; verified=$Ledger.integrity.verified; lastMissionId=$Ledger.index.lastMissionId; lastEventId=$Ledger.index.lastEventId } }

function Test-AxMissionLedger {
  param([object]$Ledger)
  $errors=New-Object System.Collections.Generic.List[string]
  if ($Ledger.schema -ne 'AX_MISSION_LEDGER_V1') { $errors.Add('SCHEMA') }
  $mids=@($Ledger.missions | ForEach-Object missionId); if ($mids.Count -ne @($mids | Sort-Object -Unique).Count) { $errors.Add('DUPLICATE_MISSION_ID') }
  $eids=@($Ledger.events | ForEach-Object eventId); if ($eids.Count -ne @($eids | Sort-Object -Unique).Count) { $errors.Add('DUPLICATE_EVENT_ID') }
  foreach($m in @($Ledger.missions)) {
    if ([string]::IsNullOrWhiteSpace($m.missionId)) { $errors.Add('MISSION_ID_MISSING') }
    if ($script:AxMissionStatuses -notcontains $m.status) { $errors.Add("STATUS_INVALID:$($m.missionId)") }
    if ($null -eq (@($Ledger.events | Where-Object missionId -eq $m.missionId | Where-Object eventId -in @($m.sourceEvents))).Count -and @($m.sourceEvents).Count -gt 0) { $errors.Add("PROJECTION_EVENT_MISSING:$($m.missionId)") }
  }
  foreach($e in @($Ledger.events)) { if ([string]::IsNullOrWhiteSpace($e.missionId) -or [string]::IsNullOrWhiteSpace($e.eventId)) { $errors.Add('EVENT_ID_MISSING') } }
  $verified=($errors.Count -eq 0)
  [pscustomobject]@{verified=$verified;errors=@($errors);missionCount=@($Ledger.missions).Count;eventCount=@($Ledger.events).Count}
}

function Save-AxMissionLedger {
  param([string]$Path='AX_MISSION_LEDGER.json',[object]$Ledger)
  $check=Test-AxMissionLedger $Ledger
  $Ledger.integrity=[ordered]@{verified=$check.verified;verificationRule='schema+unique_ids+valid_status+projection+timestamps';lastVerifiedAt=(Get-Date).ToUniversalTime().ToString('o');errors=@($check.errors)}
  $Ledger.generatedAt=(Get-Date).ToUniversalTime().ToString('o')
  $Ledger | ConvertTo-Json -Depth 30 | Set-Content -Path $Path -Encoding UTF8
  if (-not (Test-Path $Path)) { throw 'AX_MISSION_LEDGER_WRITE_FAILED' }
  return $check
}

function Load-AxMissionLedger { param([string]$Path='AX_MISSION_LEDGER.json') Get-Content -Raw $Path | ConvertFrom-Json }

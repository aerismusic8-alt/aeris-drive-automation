BeforeAll { . "$PSScriptRoot\..\AX_MISSION_LEDGER.ps1" }

Describe 'AX Mission Ledger' {
  It 'creates deterministic event ids' {
    $a=New-AxEventId 'M-001' '2026-09-02T00:00:00Z' 'chat-a' 'UPDATE' 'hello' 's1'
    $b=New-AxEventId 'M-001' '2026-09-02T00:00:00Z' 'chat-a' 'UPDATE' 'hello' 's1'
    $a | Should -Be $b
  }

  It 'creates a stable mission id' {
    (New-AxMissionId 'Build dashboard' '2026-09-02T00:00:00Z' 's1') | Should -Be (New-AxMissionId 'Build dashboard' '2026-09-02T00:00:00Z' 's1')
  }

  It 'does not duplicate a replayed event' {
    $ledger=Load-AxMissionLedger "$PSScriptRoot\..\AX_MISSION_LEDGER.json"
    $e=[pscustomobject]@{missionId='TEST-MISSION';timestamp='2026-09-02T00:00:00Z';channel='chat-a';eventType='mission.create';content='Test objective';sourceId='test-1'}
    $ledger=Upsert-AxMissionEvent $ledger $e
    $ledger=Upsert-AxMissionEvent $ledger $e
    @($ledger.events | Where-Object missionId -eq 'TEST-MISSION').Count | Should -Be 1
  }

  It 'keeps latest conversation across channels' {
    $ledger=Load-AxMissionLedger "$PSScriptRoot\..\AX_MISSION_LEDGER.json"
    $e1=[pscustomobject]@{missionId='CONTINUITY-1';timestamp='2026-09-02T00:00:00Z';channel='chat-a';eventType='mission.create';content='Original request';sourceId='c1'}
    $e2=[pscustomobject]@{missionId='CONTINUITY-1';timestamp='2026-09-02T00:01:00Z';channel='chat-b';eventType='UPDATE';content='Latest update';sourceId='c2'}
    $ledger=Upsert-AxMissionEvent $ledger $e1
    $ledger=Upsert-AxMissionEvent $ledger $e2
    $r=Resolve-AxMission $ledger 'CONTINUITY-1'
    $r.latestConversation | Should -Be 'Latest update'
    @($r.eventHistory).Count | Should -Be 2
  }

  It 'redacts obvious secrets' {
    $e=Normalize-AxMissionEvent ([pscustomobject]@{missionId='SEC-1';timestamp='2026-09-02T00:00:00Z';channel='test';eventType='UPDATE';content='token=abc123 password=xyz apiKey=secret';sourceId='s'})
    $e.content | Should -Not -Match 'abc123|xyz|secret'
    $e.content | Should -Match '\[REDACTED\]'
  }

  It 'rejects invalid mission status' {
    $ledger=Load-AxMissionLedger "$PSScriptRoot\..\AX_MISSION_LEDGER.json"
    $ledger=Upsert-AxMissionEvent $ledger ([pscustomobject]@{missionId='STATUS-1';timestamp='2026-09-02T00:00:00Z';channel='test';eventType='mission.create';content='status';sourceId='s'})
    { Set-AxMissionStatus $ledger 'STATUS-1' 'NOT_A_STATUS' } | Should -Throw
  }

  It 'verifies a valid ledger' {
    $ledger=Load-AxMissionLedger "$PSScriptRoot\..\AX_MISSION_LEDGER.json"
    $ledger=Upsert-AxMissionEvent $ledger ([pscustomobject]@{missionId='VERIFY-1';timestamp='2026-09-02T00:00:00Z';channel='test';eventType='mission.create';content='verify';sourceId='s'})
    (Test-AxMissionLedger $ledger).verified | Should -BeTrue
  }
}

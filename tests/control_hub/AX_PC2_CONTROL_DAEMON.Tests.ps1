Describe 'AX PC2 Control Daemon contract' {
    BeforeAll {
        $scriptUnderTest = Join-Path $PSScriptRoot '..\..\AX_PC_CONTROL\AX_PC2_CONTROL_DAEMON.ps1'
        . $scriptUnderTest -TestMode
    }

    It 'accepts only canonical AX commands' {
        Test-AxCommand 'STATUS' | Should -BeTrue
        Test-AxCommand 'STOP_ALL' | Should -BeTrue
        Test-AxCommand 'RESUME' | Should -BeTrue
        Test-AxCommand 'UNKNOWN' | Should -BeFalse
    }

    It 'persists and reloads state after restart' {
        $path = Join-Path $TestDrive 'state.json'
        $state = New-AxState -Status 'ONLINE' -LastCommand 'STATUS'
        Save-AxState -Path $path -State $state
        $loaded = Read-AxState -Path $path
        $loaded.status | Should -Be 'ONLINE'
        $loaded.lastCommand | Should -Be 'STATUS'
    }

    It 'treats network failure as recoverable rather than terminal' {
        Get-AxBackoffSeconds -FailureCount 1 | Should -BeGreaterThan 0
        Get-AxBackoffSeconds -FailureCount 10 | Should -BeLessOrEqual 60
    }
}

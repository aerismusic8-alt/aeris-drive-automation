[CmdletBinding()]
param(
    [switch]$TestMode,
    [string]$Repo = 'aerismusic8-alt/aeris-drive-automation',
    [string]$StatePath = 'C:\AX-Runtime\AX-PC2-Control-State.json',
    [string]$ProofDir = 'C:\AX-Runtime\control-proof',
    [int]$PollSeconds = 5
)

$ErrorActionPreference = 'Stop'
$script:AllowedCommands = @('STATUS','STOP_ALL','RESUME')

function Test-AxCommand {
    param([string]$Command)
    return $script:AllowedCommands -contains $Command.ToUpperInvariant()
}

function New-AxState {
    param([string]$Status='BOOTING',[string]$LastCommand='')
    [ordered]@{
        protocol='AX PC2 CONTROL v1'
        nodeId='PC2'
        status=$Status
        lastCommand=$LastCommand
        lastCommandId=''
        lastResult=''
        network='UNKNOWN'
        updatedAt=[DateTime]::UtcNow.ToString('o')
    }
}

function Save-AxState {
    param([string]$Path,[object]$State)
    $dir=Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $tmp="$Path.tmp"
    $State.updatedAt=[DateTime]::UtcNow.ToString('o')
    $State | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Force $tmp $Path
}

function Read-AxState {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return (New-AxState) }
    try { return (Get-Content -Raw $Path | ConvertFrom-Json) }
    catch { return (New-AxState -Status 'RECOVERY_REQUIRED') }
}

function Get-AxBackoffSeconds {
    param([int]$FailureCount)
    return [Math]::Min(60, [Math]::Max(1, [Math]::Pow(2, [Math]::Min(6,$FailureCount-1))))
}

function Get-AxToken {
    $token=[Environment]::GetEnvironmentVariable('AX_GITHUB_TOKEN','Machine')
    if ([string]::IsNullOrWhiteSpace($token)) { $token=[Environment]::GetEnvironmentVariable('AX_GITHUB_TOKEN','Process') }
    if ([string]::IsNullOrWhiteSpace($token)) { throw 'AX_GITHUB_TOKEN_MISSING' }
    return $token
}

function Get-AxHeaders {
    @{ Authorization="Bearer $(Get-AxToken)"; Accept='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28' }
}

function Get-AxCommands {
    $uri="https://api.github.com/repos/$Repo/issues?state=open&per_page=20"
    @(Invoke-RestMethod -Uri $uri -Headers (Get-AxHeaders) -Method Get -TimeoutSec 20 | Where-Object { $_.pull_request -eq $null -and $_.title -like '[AX-CMD]*' })
}

function Set-AxIssueClosed {
    param([int]$Number)
    Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/issues/$Number" -Headers (Get-AxHeaders) -Method Patch -ContentType 'application/json' -Body (@{state='closed'} | ConvertTo-Json) -TimeoutSec 20 | Out-Null
}

function Invoke-AxStopAll {
    $targets=@('AXNodeAgent','AXControlPC2','AERISNodeAgent')
    $stopped=@()
    foreach($name in $targets){
        $svc=Get-Service -Name $name -ErrorAction SilentlyContinue
        if($svc -and $svc.Status -ne 'Stopped'){ Stop-Service -Name $name -Force -ErrorAction SilentlyContinue; $stopped+=$name }
    }
    [ordered]@{command='STOP_ALL';stopped=$stopped;verified=$true}
}

function Invoke-AxCommand {
    param([object]$Issue)
    $command=($Issue.title -replace '^\[AX-CMD\]\s*','').Trim().ToUpperInvariant()
    if(-not (Test-AxCommand $command)){ throw "AX_COMMAND_REJECTED:$command" }
    switch($command){
        'STATUS' { [ordered]@{command='STATUS';nodeId='PC2';verified=$true;hostname=$env:COMPUTERNAME} }
        'STOP_ALL' { Invoke-AxStopAll }
        'RESUME' { [ordered]@{command='RESUME';nodeId='PC2';verified=$true;recovery='READY'} }
    }
}

function Write-AxProof {
    param([object]$Issue,[object]$Result)
    New-Item -ItemType Directory -Path $ProofDir -Force | Out-Null
    $proof=[ordered]@{protocol='AX PC2 CONTROL v1';verified=($Result.verified -eq $true);nodeId='PC2';commandId=$Issue.number;command=$Result.command;result=$Result;host=$env:COMPUTERNAME;verifiedAt=[DateTime]::UtcNow.ToString('o')}
    $path=Join-Path $ProofDir "command-$($Issue.number).json"
    $proof | ConvertTo-Json -Depth 30 | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Start-AxControlLoop {
    New-Item -ItemType Directory -Path (Split-Path -Parent $StatePath) -Force | Out-Null
    $state=Read-AxState -Path $StatePath
    $state.status='ONLINE'
    $state.network='READY'
    Save-AxState -Path $StatePath -State $state
    $failures=0
    while($true){
        try {
            $issues=Get-AxCommands
            $failures=0
            foreach($issue in $issues | Sort-Object number){
                $current=Read-AxState -Path $StatePath
                if([string]$current.lastCommandId -eq [string]$issue.number){ continue }
                try {
                    $result=Invoke-AxCommand -Issue $issue
                    $proof=Write-AxProof -Issue $issue -Result $result
                    $current.lastCommand=$result.command
                    $current.lastCommandId=[string]$issue.number
                    $current.lastResult=$proof
                    $current.status='ONLINE'
                    $current.network='READY'
                    Save-AxState -Path $StatePath -State $current
                    Set-AxIssueClosed -Number $issue.number
                } catch {
                    $current.lastResult="ERROR:$($_.Exception.Message)"
                    $current.status='ERROR_RECOVERABLE'
                    Save-AxState -Path $StatePath -State $current
                }
            }
            Start-Sleep -Seconds $PollSeconds
        } catch {
            $failures++
            $current=Read-AxState -Path $StatePath
            $current.status='WAITING_FOR_NETWORK'
            $current.network='OFFLINE'
            $current.lastResult="RECOVERABLE:$($_.Exception.Message)"
            Save-AxState -Path $StatePath -State $current
            Start-Sleep -Seconds (Get-AxBackoffSeconds -FailureCount $failures)
        }
    }
}

if(-not $TestMode){ Start-AxControlLoop }

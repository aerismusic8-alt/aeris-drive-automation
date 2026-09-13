[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)] [string]$ConfigPath = "$PSScriptRoot\AX_PC_NODE_CONFIG.json",
  [Parameter(Mandatory=$false)] [switch]$Once
)

$ErrorActionPreference = 'Stop'

function Read-Config {
  if (!(Test-Path -LiteralPath $ConfigPath)) { throw "CONFIG_NOT_FOUND:$ConfigPath" }
  $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
  foreach ($required in @('nodeId','controlRuntimeUrl','pollSeconds','requestTimeoutSeconds','allowedCommands')) {
    if ($null -eq $cfg.$required) { throw "CONFIG_FIELD_REQUIRED:$required" }
  }
  return $cfg
}

function Get-TransportSecret {
  $secret = [Environment]::GetEnvironmentVariable('AX_PC_PULL_SECRET','Process')
  if ([string]::IsNullOrWhiteSpace($secret)) { $secret = [Environment]::GetEnvironmentVariable('AX_PC_PULL_SECRET','Machine') }
  if ([string]::IsNullOrWhiteSpace($secret)) { throw 'AX_PC_PULL_SECRET_NOT_CONFIGURED' }
  return $secret
}

function Invoke-ControlApi([string]$Method,[string]$Path,[object]$Body,[string]$Secret,[int]$TimeoutSeconds) {
  $headers = @{ Authorization = "Bearer $Secret"; Accept = 'application/json'; 'Content-Type' = 'application/json' }
  $params = @{ Method=$Method; Uri=($script:Config.controlRuntimeUrl.TrimEnd('/')+$Path); Headers=$headers; TimeoutSec=$TimeoutSeconds; UseBasicParsing=$true }
  if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
  return Invoke-RestMethod @params
}

function Invoke-SafeProcess([string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds,[int]$MaxOutputBytes,[string]$WorkingDirectory) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  if ($WorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory)) { $psi.WorkingDirectory = $WorkingDirectory }
  $psi.Arguments = (($Arguments | ForEach-Object { '"' + ($_.Replace('\','\\').Replace('"','\"')) + '"' }) -join ' ')
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo=$psi
  $sw=[Diagnostics.Stopwatch]::StartNew()
  [void]$p.Start()
  if (!$p.WaitForExit($TimeoutSeconds*1000)) { try{$p.Kill()}catch{}; throw "COMMAND_TIMEOUT:$TimeoutSeconds" }
  $stdout=$p.StandardOutput.ReadToEnd(); $stderr=$p.StandardError.ReadToEnd(); $sw.Stop()
  if ($stdout.Length -gt $MaxOutputBytes) { $stdout=$stdout.Substring(0,$MaxOutputBytes)+'`n[OUTPUT_TRUNCATED]' }
  if ($stderr.Length -gt $MaxOutputBytes) { $stderr=$stderr.Substring(0,$MaxOutputBytes)+'`n[OUTPUT_TRUNCATED]' }
  return [pscustomobject]@{ exit_code=$p.ExitCode; stdout=$stdout; stderr=$stderr; duration_ms=$sw.ElapsedMilliseconds }
}

function Invoke-AllowedCommand($Operation,$Args,$Cfg) {
  if ($Cfg.allowedCommands -notcontains $Operation) { throw "COMMAND_NOT_ALLOWED:$Operation" }
  $maxSeconds=[int]$Cfg.terminal.maxExecutionSeconds; if($maxSeconds -le 0){$maxSeconds=300}
  $maxBytes=[int]$Cfg.terminal.maxOutputBytes; if($maxBytes -le 0){$maxBytes=65536}
  $wd=[string]$Cfg.terminal.workingDirectory
  switch ($Operation) {
    'health' { return [pscustomobject]@{ exit_code=0; stdout=("NODE_OK|"+$Cfg.nodeId+"|"+(Get-Date).ToUniversalTime().ToString('o')); stderr=''; duration_ms=0 } }
    'runner-status' {
      $services=Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'actions.runner|actions-runner|github' -or $_.DisplayName -match 'GitHub Actions|actions runner' } | Select-Object Name,DisplayName,State,StartMode
      return [pscustomobject]@{exit_code=0;stdout=($services|ConvertTo-Json -Depth 5);stderr='';duration_ms=0}
    }
    'service-status' {
      $name=[string]$Args.name; if(!$name){throw 'SERVICE_NAME_REQUIRED'}; $s=Get-Service -Name $name -ErrorAction Stop
      return [pscustomobject]@{exit_code=0;stdout=($s|Select-Object Name,Status,StartType|ConvertTo-Json);stderr='';duration_ms=0}
    }
    'service-start' { $s=Get-Service -Name ([string]$Args.name) -ErrorAction Stop; Start-Service $s.Name; return Invoke-AllowedCommand 'service-status' $Args $Cfg }
    'service-stop' { $s=Get-Service -Name ([string]$Args.name) -ErrorAction Stop; Stop-Service $s.Name -Force; return Invoke-AllowedCommand 'service-status' $Args $Cfg }
    'service-restart' { $s=Get-Service -Name ([string]$Args.name) -ErrorAction Stop; Restart-Service $s.Name -Force; return Invoke-AllowedCommand 'service-status' $Args $Cfg }
    'runner-start' { $s=Get-CimInstance Win32_Service | Where-Object {$_.Name -match 'actions.runner|actions-runner'} | Select-Object -First 1; if(!$s){throw 'RUNNER_SERVICE_NOT_FOUND'}; Start-Service $s.Name; return Invoke-AllowedCommand 'runner-status' $Args $Cfg }
    'runner-stop' { $s=Get-CimInstance Win32_Service | Where-Object {$_.Name -match 'actions.runner|actions-runner'} | Select-Object -First 1; if(!$s){throw 'RUNNER_SERVICE_NOT_FOUND'}; Stop-Service $s.Name -Force; return Invoke-AllowedCommand 'runner-status' $Args $Cfg }
    'runner-restart' { $s=Get-CimInstance Win32_Service | Where-Object {$_.Name -match 'actions.runner|actions-runner'} | Select-Object -First 1; if(!$s){throw 'RUNNER_SERVICE_NOT_FOUND'}; Restart-Service $s.Name -Force; return Invoke-AllowedCommand 'runner-status' $Args $Cfg }
    'task-status' { $name=[string]$Args.name; if(!$name){throw 'TASK_NAME_REQUIRED'}; $t=Get-ScheduledTask -TaskName $name -ErrorAction Stop; $i=Get-ScheduledTaskInfo -TaskName $name; return [pscustomobject]@{exit_code=0;stdout=(@{TaskName=$t.TaskName;State=$t.State;LastRunTime=$i.LastRunTime;NextRunTime=$i.NextRunTime}|ConvertTo-Json);stderr='';duration_ms=0} }
    'process-status' { $name=[string]$Args.name; $p=if($name){Get-Process -Name $name -ErrorAction SilentlyContinue}else{Get-Process}; return [pscustomobject]@{exit_code=0;stdout=($p|Select-Object Id,ProcessName,CPU|ConvertTo-Json);stderr='';duration_ms=0} }
    'git-status' { return Invoke-SafeProcess 'git.exe' @('status','--short','--branch') $maxSeconds $maxBytes $wd }
    'terminal-powershell' {
      $cmd=[string]$Args.command; if([string]::IsNullOrWhiteSpace($cmd)){throw 'COMMAND_REQUIRED'}
      $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
      return Invoke-SafeProcess 'powershell.exe' @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) $maxSeconds $maxBytes $wd
    }
    default { throw "UNKNOWN_COMMAND:$Operation" }
  }
}

function Process-Item($Item,$Cfg,$Secret) {
  $requestId=[string]$Item.request_id; $taskId=[string]$Item.task_id
  if(!$requestId -or !$taskId){throw 'REQUEST_OR_TASK_ID_MISSING'}

  $operation=''
  $args=@{}
  $parseError=$null

  try {
    if($Item.content){
      try {
        $parsed=$Item.content | ConvertFrom-Json -ErrorAction Stop
        if(!$parsed.operation){ throw 'OPERATION_REQUIRED: content must be JSON with an explicit operation' }
        $operation=[string]$parsed.operation
        if($null -ne $parsed.args){ $args=$parsed.args }
      } catch {
        $parseError=$_.Exception.Message
        if($parseError -like 'OPERATION_REQUIRED:*'){ throw $parseError }
        throw 'INVALID_OPERATION_PAYLOAD: content must be valid JSON with an explicit operation'
      }
    } elseif($Cfg.allowedCommands -contains [string]$Item.content_type) {
      $operation=[string]$Item.content_type
    } else {
      throw ("OPERATION_REQUIRED: content_type={0}" -f [string]$Item.content_type)
    }

    $r=Invoke-AllowedCommand $operation $args $Cfg
    $result=@{accepted=$true;executed=($r.exit_code -eq 0);verified=($r.exit_code -eq 0);requestId=$requestId;taskId=$taskId;status=if($r.exit_code -eq 0){'VERIFIED'}else{'EXECUTION_FAILED'};node_id=$Cfg.nodeId;exit_code=$r.exit_code;stdout=$r.stdout;stderr=$r.stderr;duration_ms=$r.duration_ms;evidence=@{taskId=$taskId;nodeId=$Cfg.nodeId;command=$operation};writeBackVerified=$true}
  } catch {
    $result=@{accepted=$true;executed=$false;verified=$false;requestId=$requestId;taskId=$taskId;status='EXECUTION_FAILED';node_id=$Cfg.nodeId;error=$_.Exception.Message;writeBackVerified=$false;evidence=@{taskId=$taskId;nodeId=$Cfg.nodeId;command=$operation}}
  }

  Invoke-ControlApi 'POST' '/pc/result' @{request_id=$requestId;task_id=$taskId;result=$result} $Secret $Cfg.requestTimeoutSeconds | Out-Null
  Invoke-ControlApi 'POST' '/pc/ack' @{request_id=$requestId} $Secret $Cfg.requestTimeoutSeconds | Out-Null
  return $result
}

$script:Config=Read-Config
$secret=Get-TransportSecret
while($true){
  try {
    $response=Invoke-ControlApi 'POST' '/pc/pull' $null $secret $script:Config.requestTimeoutSeconds
    if($response.item){
      $result=Process-Item $response.item $script:Config $secret
      if($Once){ Write-Output ("AX_PC_NODE_RESULT|" + ($result | ConvertTo-Json -Depth 20 -Compress)) }
    } elseif($Once) {
      Write-Output 'AX_PC_NODE_PULL|EMPTY'
    }
  } catch {
    Write-Error ("AX_PC_NODE_ERROR|"+$_.Exception.Message)
  }
  if($Once){break}
  Start-Sleep -Seconds ([Math]::Max(2,[int]$script:Config.pollSeconds))
}

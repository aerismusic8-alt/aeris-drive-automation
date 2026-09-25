param([string]$RuntimeRoot='C:\AX-Runtime',[int]$Port=18761)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$queue=Join-Path $RuntimeRoot 'brain1-intent-queue\pending'
$ev=Join-Path $RuntimeRoot 'evidence'
New-Item -ItemType Directory -Force -Path $queue,$ev|Out-Null
$listener=[Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
while($listener.IsListening){
  $ctx=$null
  try{
    $ctx=$listener.GetContext();$req=$ctx.Request;$res=$ctx.Response;$body=''
    if($req.HttpMethod -eq 'GET' -and $req.Url.AbsolutePath -eq '/health'){
      $body=@{status='ALIVE';nodeId='PC1';computerName=$env:COMPUTERNAME;gateway='LOCAL';timestampUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json
    }elseif($req.HttpMethod -eq 'POST' -and $req.Url.AbsolutePath -eq '/intent'){
      $reader=[IO.StreamReader]::new($req.InputStream,$req.ContentEncoding);$raw=$reader.ReadToEnd();$reader.Dispose()
      $i=$raw|ConvertFrom-Json
      if($i.targetNode -ne 'PC1'){throw 'TARGET_NODE_NOT_PC1'}
      if(!$i.jobId){throw 'JOB_ID_MISSING'}
      $allowed=@('NODE_HEALTH_CHECK','SYSTEM_DIAGNOSTIC','CLOSE_STALE_TERMINAL','CAPTURE_AND_REVERIFY','RESTART_OWNED_RUNTIME','INCIDENT_LOCAL_DIAGNOSE')
      if($allowed -notcontains $i.intent){throw 'BRAIN_INTENT_NOT_ALLOWED'}
      $i|ConvertTo-Json -Depth 10|Set-Content (Join-Path $queue "$($i.jobId).json") -Encoding UTF8
      $body=@{accepted=$true;nodeId='PC1';jobId=$i.jobId;queuedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json
    }else{$res.StatusCode=404;$body='NOT_FOUND'}
    $bytes=[Text.Encoding]::UTF8.GetBytes($body);$res.ContentType='application/json';$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);$res.Close()
  }catch{
    if($ctx){$res=$ctx.Response;$res.StatusCode=500;$bytes=[Text.Encoding]::UTF8.GetBytes((@{error=$_.Exception.Message}|ConvertTo-Json));$res.OutputStream.Write($bytes,0,$bytes.Length);$res.Close()}
  }
}
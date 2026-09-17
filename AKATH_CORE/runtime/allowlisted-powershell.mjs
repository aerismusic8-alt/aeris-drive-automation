import { spawn } from 'node:child_process';

const ACTIONS = Object.freeze({
  runtime_heartbeat: Object.freeze({
    script: 'Write-Output "AX_PC1_RUNTIME_HEARTBEAT"'
  }),
  runtime_status: Object.freeze({
    script: 'Write-Output "AX_PC1_RUNTIME_STATUS"'
  }),
  runtime_identity: Object.freeze({
    script: '$id=[ordered]@{computerName=$env:COMPUTERNAME;userName="$env:USERDOMAIN\\$env:USERNAME";nodeId=$env:AX_PC1_NODE_ID;processId=$PID;powershellVersion=$PSVersionTable.PSVersion.ToString()};$id|ConvertTo-Json -Compress'
  }),
  runtime_process_snapshot: Object.freeze({
    script: 'Get-Process | Where-Object { $_.ProcessName -match "node|powershell" } | Select-Object -First 20 Id,ProcessName | Format-Table -AutoSize | Out-String'
  }),
  runtime_disk_snapshot: Object.freeze({
    script: 'Get-PSDrive -PSProvider FileSystem | Select-Object Name,Free,Used | Format-Table -AutoSize | Out-String'
  }),
  jumtask: Object.freeze({
    script: '$out = if ($env:AX_PC2_JUMTASK_OUTPUT) { $env:AX_PC2_JUMTASK_OUTPUT } else { Join-Path $env:TEMP "AERIS_JUMTASK_OUTPUT.txt" }; Start-Sleep -Milliseconds 500; Write-Output "[JUMTASK] STEP=WORK"; Start-Sleep -Milliseconds 700; Write-Output "[JUMTASK] STEP=VERIFY"; Start-Sleep -Milliseconds 500; $record = "JUMTASK_OK|HOST=$env:COMPUTERNAME|USER=$env:USERNAME|UTC=$([DateTime]::UtcNow.ToString("o"))"; Set-Content -Path $out -Value $record -Encoding UTF8; Write-Output "[JUMTASK] OUTPUT=$out"; Write-Output "[JUMTASK] RESULT=JUMTASK_OK"'
  }),
  youtube_short_package: Object.freeze({
    script: '$root = if ($env:AX_PC2_REVENUE_OUTPUT) { $env:AX_PC2_REVENUE_OUTPUT } else { Join-Path $PSScriptRoot "AERIS_REVENUE_OUTPUT" }; New-Item -ItemType Directory -Force -Path $root | Out-Null; $taskId = if ($env:AX_PC2_REVENUE_TASK_ID) { $env:AX_PC2_REVENUE_TASK_ID } else { "PC2-REV-YT-SHORT-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())" }; $title = if ($env:AX_PC2_REVENUE_TITLE) { $env:AX_PC2_REVENUE_TITLE } else { "AERIS Music — YouTube Short" }; $ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue; if (-not $ffmpeg) { throw "FFMPEG_NOT_FOUND" }; $mp4 = Join-Path $root "AERIS_SHORT.mp4"; & $ffmpeg.Source -hide_banner -loglevel error -y -f lavfi -i "color=c=black:s=1080x1920:r=30" -t 3 -vf "drawtext=text=''AERIS MUSIC'':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2" -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart $mp4; if ($LASTEXITCODE -ne 0 -or -not (Test-Path $mp4)) { throw "MP4_RENDER_FAILED" }; $bytes=(Get-Item $mp4).Length; if ($bytes -le 10000) { throw "MP4_OUTPUT_TOO_SMALL" }; $manifest = [ordered]@{taskId=$taskId;channel="AERISMusicTH";type="youtube_short_package";title=$title;createdAt=[DateTime]::UtcNow.ToString("o");status="READY_FOR_QC";mp4=$mp4;mp4Bytes=$bytes;autonomous=$true}; $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $root "manifest.json") -Encoding UTF8; $metadata = [ordered]@{channel="AERISMusicTH";title=$title;description="AERIS MUSIC autonomous short package";tags=@("AERISMusicTH","AERIS MUSIC","AI Music")}; $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $root "metadata.json") -Encoding UTF8; Set-Content -Path (Join-Path $root "script.txt") -Value "MP4 rendered and ready for QC: $mp4" -Encoding UTF8; Write-Output "[REVENUE] MP4=$mp4"; Write-Output "[REVENUE] BYTES=$bytes"; Write-Output "[REVENUE] OUTPUT=$root"; Write-Output "[REVENUE] RESULT=YOUTUBE_SHORT_PACKAGE_READY"'
  })
});

export function listAllowlistedActions() {
  return Object.keys(ACTIONS);
}

export async function executeAllowlistedPowerShell(action, { onStdout, onStderr } = {}) {
  const spec = ACTIONS[action];
  if (!spec) throw new Error(`PowerShell action not allowlisted: ${action}`);

  return new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', spec.script
    ], {
      shell: false,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => {
      const text = chunk.toString();
      stdout += text;
      onStdout?.(text);
    });
    child.stderr.on('data', chunk => {
      const text = chunk.toString();
      stderr += text;
      onStderr?.(text);
    });
    child.on('error', reject);
    child.on('close', exitCode => resolve({ action, stdout: stdout.trim(), stderr: stderr.trim(), exitCode }));
  });
}
Set-StrictMode -Version Latest

$AX_CLOUD_TIME_URL = if ($env:AX_CLOUD_TIME_URL) { $env:AX_CLOUD_TIME_URL } else { 'https://ax-control-runtime.aerismusic8.workers.dev/time' }

function ConvertTo-AxDateTime {
    param([Parameter(Mandatory)][string]$Value)
    try { return [DateTimeOffset]::Parse($Value) }
    catch { throw "รูปแบบวันเวลาไม่ถูกต้อง: $Value" }
}

function Get-AxCloudTime {
    param([string]$Url = $AX_CLOUD_TIME_URL)
    try {
        $response = Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 20
        if (-not $response.timestampUtc -or $null -eq $response.epochMs) { throw 'CLOUD_TIME_RESPONSE_INVALID' }
        [pscustomobject]@{
            TimestampUtc = (ConvertTo-AxDateTime ([string]$response.timestampUtc)).ToString('o')
            EpochMs = [int64]$response.epochMs
            Source = [string]$response.source
            Authority = [string]$response.authority
            RequestId = [string]$response.requestId
            TimezoneDisplay = [string]$response.timezoneDisplay
            TimestampThailand = [string]$response.timestampThailand
        }
    } catch {
        throw "ไม่สามารถยืนยันเวลาจากคลาวด์ได้: $($_.Exception.Message)"
    }
}

function Get-AxElapsedMinutes {
    param(
        [Parameter(Mandatory)][string]$Start,
        [Parameter(Mandatory)][string]$End
    )
    $startTime = ConvertTo-AxDateTime $Start
    $endTime = ConvertTo-AxDateTime $End
    if ($endTime -lt $startTime) { throw 'เวลาจบต้องไม่มาก่อนเวลาเริ่ม' }
    return [int][Math]::Round(($endTime - $startTime).TotalMinutes, 0)
}

function Get-AxTimingAssessment {
    param(
        [Parameter(Mandatory)][int]$ElapsedMinutes,
        [Parameter(Mandatory)][int]$TargetMinutes
    )
    if ($TargetMinutes -lt 0 -or $ElapsedMinutes -lt 0) { throw 'เวลาต้องไม่ติดลบ' }
    $variance = $TargetMinutes - $ElapsedMinutes
    if ($variance -gt 0) { $status = 'เร็วกว่ากำหนด' }
    elseif ($variance -lt 0) { $status = 'ช้ากว่ากำหนด' }
    else { $status = 'ตรงตามกำหนด' }
    [pscustomobject]@{
        Status = $status
        VarianceMinutes = [Math]::Abs($variance)
        TargetMinutes = $TargetMinutes
        ElapsedMinutes = $ElapsedMinutes
    }
}

function New-AxTimingRecord {
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][int]$TargetMinutes
    )
    [pscustomobject]@{
        TaskId = $TaskId
        TargetMinutes = $TargetMinutes
        ActualStart = $null
        ActualEnd = $null
        PauseResume = @()
        ActualElapsedMinutes = $null
        TimingStatus = 'ยังไม่เริ่ม'
        TimeAuthority = 'AX_CLOUD_TIME_AUTHORITY'
        Evidence = @()
    }
}

function Start-AxTaskTiming {
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][hashtable]$Evidence,
        [string]$CloudTimeUrl = $AX_CLOUD_TIME_URL
    )
    if ([string]::IsNullOrWhiteSpace($Evidence.Type) -or [string]::IsNullOrWhiteSpace($Evidence.Reference)) {
        throw 'การเริ่มเวลาจริงต้องมีหลักฐาน'
    }
    $cloudTime = Get-AxCloudTime -Url $CloudTimeUrl
    [pscustomobject]@{
        TaskId = $TaskId
        ActualStart = $cloudTime.TimestampUtc
        ActualStartEpochMs = $cloudTime.EpochMs
        TimeAuthority = $cloudTime.Source
        TimeAuthorityRequestId = $cloudTime.RequestId
        Evidence = @([pscustomobject]@{
            Type = $Evidence.Type
            Reference = $Evidence.Reference
            RecordedAt = $cloudTime.TimestampUtc
            TimeAuthority = $cloudTime.Source
        })
    }
}

function Get-AxTimingEvent {
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][ValidateSet('START','END','PAUSE','RESUME','STATUS_CHANGE')][string]$EventType,
        [Parameter(Mandatory)][hashtable]$Evidence,
        [string]$CloudTimeUrl = $AX_CLOUD_TIME_URL
    )
    if ([string]::IsNullOrWhiteSpace($Evidence.Type) -or [string]::IsNullOrWhiteSpace($Evidence.Reference)) {
        throw 'เหตุการณ์เวลาจริงต้องมีหลักฐาน'
    }
    $cloudTime = Get-AxCloudTime -Url $CloudTimeUrl
    [pscustomobject]@{
        TaskId = $TaskId
        EventType = $EventType
        TimestampUtc = $cloudTime.TimestampUtc
        EpochMs = $cloudTime.EpochMs
        TimeAuthority = $cloudTime.Source
        TimeAuthorityRequestId = $cloudTime.RequestId
        Evidence = [pscustomobject]@{
            Type = $Evidence.Type
            Reference = $Evidence.Reference
        }
    }
}

Set-StrictMode -Version Latest

function ConvertTo-AxDateTime {
    param([Parameter(Mandatory)][string]$Value)
    try { return [DateTimeOffset]::Parse($Value) }
    catch { throw "รูปแบบวันเวลาไม่ถูกต้อง: $Value" }
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
    if ($variance -gt 0) {
        $status = 'เร็วกว่ากำหนด'
    } elseif ($variance -lt 0) {
        $status = 'ช้ากว่ากำหนด'
    } else {
        $status = 'ตรงตามกำหนด'
    }
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
        Evidence = @()
    }
}

function Start-AxTaskTiming {
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$StartTime,
        [Parameter(Mandatory)][hashtable]$Evidence
    )
    if ([string]::IsNullOrWhiteSpace($Evidence.Type) -or [string]::IsNullOrWhiteSpace($Evidence.Reference)) {
        throw 'การเริ่มเวลาจริงต้องมีหลักฐาน'
    }
    $start = ConvertTo-AxDateTime $StartTime
    [pscustomobject]@{
        TaskId = $TaskId
        ActualStart = $start.ToString('o')
        Evidence = @([pscustomobject]@{
            Type = $Evidence.Type
            Reference = $Evidence.Reference
            RecordedAt = (Get-Date).ToUniversalTime().ToString('o')
        })
    }
}

$ErrorActionPreference = 'Stop'

$module = Join-Path $PSScriptRoot '..' 'AX_EXECUTION_TIMING.ps1'
. $module

function Assert-Equal($actual, $expected, $name) {
    if ($actual -ne $expected) { throw "$name: expected [$expected], got [$actual]" }
}

# เวลาใช้จริงจากเริ่ม 10:00 ถึง 10:37 ต้องเป็น 37 นาที
$elapsed = Get-AxElapsedMinutes -Start '2026-09-02T10:00:00+07:00' -End '2026-09-02T10:37:00+07:00'
Assert-Equal $elapsed 37 'elapsed minutes'

# งานใช้ 37 จากเป้าหมาย 45 นาที = เร็วกว่าแผน
$assessment = Get-AxTimingAssessment -ElapsedMinutes 37 -TargetMinutes 45
Assert-Equal $assessment.Status 'เร็วกว่ากำหนด' 'status fast'
Assert-Equal $assessment.VarianceMinutes 8 'variance fast'

# งานใช้ 55 จากเป้าหมาย 45 นาที = ช้ากว่าแผน 10 นาที
$assessment = Get-AxTimingAssessment -ElapsedMinutes 55 -TargetMinutes 45
Assert-Equal $assessment.Status 'ช้ากว่ากำหนด' 'status slow'
Assert-Equal $assessment.VarianceMinutes 10 'variance slow'

# งานยังไม่เริ่มต้องไม่มีเวลาจริง
$notStarted = New-AxTimingRecord -TaskId 'TEST-001' -TargetMinutes 45
Assert-Equal $notStarted.ActualStart $null 'not started actual start'
Assert-Equal $notStarted.ActualElapsedMinutes $null 'not started elapsed'

# เวลาเริ่มจริงต้องมีหลักฐานประกอบ
try {
    Start-AxTaskTiming -TaskId 'TEST-001' -StartTime '2026-09-02T10:00:00+07:00'
    throw 'expected evidence validation failure'
} catch {
    if ($_.Exception.Message -notmatch 'หลักฐาน') { throw }
}

Write-Output 'PASS: AX execution timing tests'

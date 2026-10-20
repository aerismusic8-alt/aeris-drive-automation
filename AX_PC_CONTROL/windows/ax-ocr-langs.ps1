# Which languages can Windows OCR actually read on this machine?
#
# The Thai Windows language pack is installed but the OCR feature for it was not
# in the image, so this asks the recogniser directly rather than inferring from
# the installed packages. It decides whether reading the game's Thai interface is
# possible here at all, or whether the frame-diff approach has to stay the way
# the agent follows the game.
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

Write-Output 'AVAILABLE_RECOGNIZER_LANGUAGES:'
$any = $false
foreach ($l in [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages) {
  $any = $true
  Write-Output ("  " + $l.LanguageTag + "  " + $l.DisplayName)
}
if (-not $any) { Write-Output '  (none)' }

$thai = New-Object Windows.Globalization.Language('th-TH')
Write-Output ("THAI_SUPPORTED=" + [Windows.Media.Ocr.OcrEngine]::IsLanguageSupported($thai))
Write-Output ("ENGINE_FROM_THAI_NULL=" + ($null -eq [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($thai)))

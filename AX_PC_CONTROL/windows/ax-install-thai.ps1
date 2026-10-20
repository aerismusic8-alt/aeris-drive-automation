# Install the Thai OCR language so the game's own text can be read.
#
# The game interface is Thai and Windows OCR here only ships en-US, so every
# reading of it comes back as mojibake. That is the one gap that stops the agent
# understanding the game rather than merely seeing it change, so it is worth
# installing properly.
#
# Add-WindowsCapability answers in well over the 30 second cap on a remote call
# and returns nothing when it is cut off, so this is written to log progress
# after each step. Run it detached and poll the log rather than waiting inline.
#
# It is best effort: if the feature is not in this image, or Windows Update is
# unreachable, it reports that plainly instead of pretending to have installed.
$ErrorActionPreference = 'Continue'
$log = "$env:TEMP\ax-thai-install.log"
function Say($m) { "$([DateTime]::Now.ToString('HH:mm:ss')) $m" | Tee-Object -FilePath $log -Append | Out-Null }

Say 'START'
try {
  Say ("OS=" + (Get-CimInstance Win32_OperatingSystem).Caption + " build=" + [Environment]::OSVersion.Version)
  Say ("current=" + ([System.Globalization.CultureInfo]::CurrentUICulture.Name))

  Say 'listing Thai OCR capabilities'
  $caps = Get-WindowsCapability -Online | Where-Object { $_.Name -match 'th-TH' }
  foreach ($c in $caps) { Say ("CAP " + $c.Name + " state=" + $c.State) }

  $ocr = $caps | Where-Object { $_.Name -like 'Language.OCR*' } | Select-Object -First 1
  if ($null -eq $ocr) {
    Say 'NO_OCR_CAPABILITY_FOUND reason=image_has_no_thai_ocr_feature'
  } elseif ($ocr.State -eq 'Installed') {
    Say 'OCR_ALREADY_INSTALLED'
  } else {
    Say ("installing " + $ocr.Name)
    $r = Add-WindowsCapability -Online -Name $ocr.Name
    Say ("INSTALL_RESULT=" + $r.RestartNeeded + " state=" + $r.Online)
  }

  # Registering the language is what actually makes the recogniser offer Thai;
  # installing the capability alone can leave it unselectable.
  Say 'adding th-TH to the user language list'
  $list = New-WinUserLanguageList th-TH
  Set-WinUserLanguageList -LanguageList $list -Force
  Say 'language list updated'

  Say 'OCR engines now available'
  foreach ($l in [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages) {
    Say ("ENGINE " + $l.LanguageTag + " " + $l.DisplayName)
  }
  Say 'OK'
} catch {
  Say ("ERR " + $_.Exception.Message)
}
Say 'DONE'

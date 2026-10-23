# Launch the live Breachline experience on PC1's interactive desktop and
# photograph it, in one step.
#
# This exists because of where the player has to run. A Roblox player started
# through the MCP Shell tool lives in the runner's service session, which has no
# desktop: the process appears in the process list but never owns a visible
# window, so a capture finds nothing and there is nothing to prove. Starting the
# launch from a workflow step puts the player on the interactive desktop, where
# it draws, and the capture below then has a real frame to save.
#
# The wrapper carries the arguments because the workflow runs a pre_command with
# no parameters of its own.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$capture = Join-Path $here 'pc1-capture-window.ps1'
if (-not (Test-Path -LiteralPath $capture)) {
  $raw = "https://raw.githubusercontent.com/aerismusic8-alt/aeris-drive-automation/$($env:GITHUB_REF_NAME)/AX_PC_CONTROL/pc1-capture-window.ps1"
  Invoke-WebRequest -Uri $raw -OutFile $capture -UseBasicParsing
}

& $capture -ProcessName RobloxPlayerBeta `
  -OutDir 'C:\AX-Runtime\evidence\capture' `
  -LaunchPlaceId '136310542172942' `
  -LaunchWaitSeconds 120 `
  -WaitSeconds 6

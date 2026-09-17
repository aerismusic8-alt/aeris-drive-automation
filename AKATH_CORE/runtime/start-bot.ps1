$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')
& (Join-Path $PSScriptRoot 'start-ax-runtime.ps1') -NodeId 'PC2-MAIN' -Specialist 'pc2-specialist.mjs' -ControlSpecialist 'pc2-specialist.mjs'

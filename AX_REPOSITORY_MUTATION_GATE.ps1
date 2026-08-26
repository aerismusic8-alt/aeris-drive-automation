```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$FilePath,

  [Parameter(Mandatory = $true)]
  [string]$Content,

  [string]$CommitMessage = 'AX controlled repository mutation'
)

$ErrorActionPreference = 'Stop'

Write-Host '=== AX REPOSITORY MUTATION GATE ==='

# ------------------------------------------------------------
# SAFETY POLICY
# ------------------------------------------------------------

$repoRoot = (Get-Location).Path
$normalizedPath = $FilePath.Replace('\','/').TrimStart('/')

if ($normalizedPath -match '(^|/)\.git(/|$)') {
  throw 'REPOSITORY_MUTATION_BLOCKED_GIT_INTERNAL'
}

if ($normalizedPath -match '(^|/)(\.github/workflows/.*secrets|.*secret.*|.*credentials.*)$') {
  throw 'REPOSITORY_MUTATION_BLOCKED_SENSITIVE_PATH'
}

$allowedExtensions = @(
  '.ps1',
  '.json',
  '.jsonc',
  '.ts',
  '.js',
  '.mjs',
  '.yml',
  '.yaml',
  '.md',
  '.txt'
)

$extension = [System.IO.Path]::GetExtension($normalizedPath)

if ($extension -notin $allowedExtensions) {
  throw "REPOSITORY_MUTATION_BLOCKED_EXTENSION:$extension"
}

# ------------------------------------------------------------
# MAIN-BRANCH SAFETY
# ------------------------------------------------------------

$branch = git branch --show-current

if ($LASTEXITCODE -ne 0) {
  throw 'GIT_BRANCH_DETECTION_FAILED'
}

Write-Host "Branch: $branch"

if ($branch -ne 'main') {
  throw "REPOSITORY_MUTATION_REQUIRES_MAIN:$branch"
}

# ------------------------------------------------------------
# FILE PATH SAFETY
# ------------------------------------------------------------

$targetPath = Join-Path $repoRoot $normalizedPath
$targetDirectory = Split-Path -Parent $targetPath

if (-not (Test-Path $targetDirectory)) {
  New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
}

# ------------------------------------------------------------
# BACKUP EXISTING CONTENT
# ------------------------------------------------------------

$existing = $null

if (Test-Path $targetPath) {
  $existing = Get-Content -Raw -Path $targetPath
  Write-Host "Existing file detected: $normalizedPath"
}
else {
  Write-Host "Creating new file: $normalizedPath"
}

# ------------------------------------------------------------
# WRITE
# ------------------------------------------------------------

[System.IO.File]::WriteAllText(
  $targetPath,
  $Content,
  [System.Text.UTF8Encoding]::new($false)
)

Write-Host 'File write: PASS'

# ------------------------------------------------------------
# VERIFY CONTENT
# ------------------------------------------------------------

$verifiedContent = Get-Content -Raw -Path $targetPath

if ($verifiedContent -ne $Content) {
  throw 'REPOSITORY_MUTATION_CONTENT_VERIFICATION_FAILED'
}

Write-Host 'Content verification: PASS'

# ------------------------------------------------------------
# GIT STATUS
# ------------------------------------------------------------

git status --short

if ($LASTEXITCODE -ne 0) {
  throw 'GIT_STATUS_FAILED'
}

# ------------------------------------------------------------
# STAGE ONLY REQUESTED FILE
# ------------------------------------------------------------

git add -- $normalizedPath

if ($LASTEXITCODE -ne 0) {
  throw 'GIT_STAGE_FAILED'
}

Write-Host "Staged: $normalizedPath"

# ------------------------------------------------------------
# VERIFY STAGED PATH
# ------------------------------------------------------------

$staged = git diff --cached --name-only

if ($LASTEXITCODE -ne 0) {
  throw 'GIT_STAGED_FILE_CHECK_FAILED'
}

if ($staged -notcontains $normalizedPath) {
  throw 'REPOSITORY_MUTATION_STAGE_VERIFICATION_FAILED'
}

$unexpected = @(
  $staged | Where-Object { $_ -ne $normalizedPath }
)

if ($unexpected.Count -gt 0) {
  git reset
  throw "REPOSITORY_MUTATION_UNEXPECTED_FILES:$($unexpected -join ',')"
}

Write-Host 'Staged-path verification: PASS'

# ------------------------------------------------------------
# COMMIT
# ------------------------------------------------------------

git commit -m $CommitMessage

if ($LASTEXITCODE -ne 0) {
  throw 'GIT_COMMIT_FAILED'
}

Write-Host 'Commit: PASS'

# ------------------------------------------------------------
# FINAL VERIFICATION
# ------------------------------------------------------------

$commitSha = (git rev-parse HEAD).Trim()

if ([string]::IsNullOrWhiteSpace($commitSha)) {
  throw 'COMMIT_SHA_VERIFICATION_FAILED'
}

Write-Host "Commit SHA: $commitSha"

$workingTree = git status --porcelain

if (-not [string]::IsNullOrWhiteSpace(($workingTree | Out-String).Trim())) {
  throw 'REPOSITORY_NOT_CLEAN_AFTER_MUTATION'
}

Write-Host 'Working tree: CLEAN'
Write-Host 'Repository mutation: VERIFIED'
Write-Host 'Live financial execution: DISABLED'
Write-Host '=== AX REPOSITORY MUTATION GATE COMPLETE ==='
```

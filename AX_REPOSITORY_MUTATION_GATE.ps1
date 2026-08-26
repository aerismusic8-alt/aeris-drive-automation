param(
  [Parameter(Mandatory = $true)]
  [string]$FilePath,

  [Parameter(Mandatory = $true)]
  [string]$Content,

  [string]$CommitMessage = 'AX controlled repository mutation'
)

$ErrorActionPreference = 'Stop'

Write-Host '=== AX REPOSITORY MUTATION GATE ==='

# ============================================================
# REPOSITORY ROOT
# ============================================================

$repoRoot = (Get-Location).Path
$repoRootFull = [System.IO.Path]::GetFullPath($repoRoot)

# ============================================================
# MUTATION ENABLEMENT
# ============================================================

if ($env:AX_REPOSITORY_MUTATION_ENABLED -ne 'true') {
  throw 'REPOSITORY_MUTATION_DISABLED_BY_POLICY'
}

Write-Host 'Mutation capability: ENABLED'

# ============================================================
# PATH NORMALIZATION / SAFETY
# ============================================================

$normalizedPath = $FilePath.Replace('\','/').TrimStart('/')

if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
  throw 'REPOSITORY_MUTATION_INVALID_PATH'
}

if ($normalizedPath -match '(^|/)\.\.?(/|$)') {
  throw 'REPOSITORY_MUTATION_BLOCKED_PATH_TRAVERSAL'
}

if ($normalizedPath -match '(^|/)\.git(/|$)') {
  throw 'REPOSITORY_MUTATION_BLOCKED_GIT_INTERNAL'
}

if ($normalizedPath -match '(^|/)(.*secret.*|.*credential.*|.*token.*)$') {
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

# ============================================================
# TARGET PATH MUST REMAIN INSIDE REPOSITORY
# ============================================================

$targetPath = [System.IO.Path]::GetFullPath(
  (Join-Path $repoRootFull $normalizedPath)
)

$repoPrefix = $repoRootFull.TrimEnd('\') + '\'

if (-not $targetPath.StartsWith(
  $repoPrefix,
  [System.StringComparison]::OrdinalIgnoreCase
)) {
  throw 'REPOSITORY_MUTATION_BLOCKED_OUTSIDE_REPOSITORY'
}

Write-Host "Target: $normalizedPath"

# ============================================================
# MAIN BRANCH SAFETY
# ============================================================

$branch = (git branch --show-current).Trim()

if ($LASTEXITCODE -ne 0) {
  throw 'GIT_BRANCH_DETECTION_FAILED'
}

Write-Host "Branch: $branch"

if ($branch -ne 'main') {
  throw "REPOSITORY_MUTATION_REQUIRES_MAIN:$branch"
}

# ============================================================
# DIRECTORY
# ============================================================

$targetDirectory = Split-Path -Parent $targetPath

if (-not (Test-Path $targetDirectory)) {
  New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
}

# ============================================================
# WRITE
# ============================================================

if (Test-Path $targetPath) {
  Write-Host "Existing file detected: $normalizedPath"
}
else {
  Write-Host "Creating new file: $normalizedPath"
}

[System.IO.File]::WriteAllText(
  $targetPath,
  $Content,
  [System.Text.UTF8Encoding]::new($false)
)

Write-Host 'File write: PASS'

# ============================================================
# CONTENT VERIFICATION
# ============================================================

$verifiedContent = Get-Content -Raw -Path $targetPath

if ($verifiedContent -ne $Content) {
  throw 'REPOSITORY_MUTATION_CONTENT_VERIFICATION_FAILED'
}

Write-Host 'Content verification: PASS'

# ============================================================
# STAGE ONLY REQUESTED FILE
# ============================================================

git add -- $normalizedPath

if ($LASTEXITCODE -ne 0) {
  throw 'GIT_STAGE_FAILED'
}

Write-Host "Staged: $normalizedPath"

# ============================================================
# STAGED PATH VERIFICATION
# ============================================================

$staged = @(git diff --cached --name-only)

if ($LASTEXITCODE -ne 0) {
  throw 'GIT_STAGED_FILE_CHECK_FAILED'
}

if ($staged.Count -ne 1 -or $staged[0] -ne $normalizedPath) {
  git reset -- $normalizedPath
  throw "REPOSITORY_MUTATION_UNEXPECTED_STAGED_FILES:$($staged -join ',')"
}

Write-Host 'Staged-path verification: PASS'

# ============================================================
# COMMIT
# ============================================================

git commit -m $CommitMessage

if ($LASTEXITCODE -ne 0) {
  throw 'GIT_COMMIT_FAILED'
}

Write-Host 'Commit: PASS'

# ============================================================
# LOCAL COMMIT VERIFICATION
# ============================================================

$commitSha = (git rev-parse HEAD).Trim()

if ([string]::IsNullOrWhiteSpace($commitSha)) {
  throw 'COMMIT_SHA_VERIFICATION_FAILED'
}

Write-Host "Local Commit SHA: $commitSha"

# ============================================================
# WORKING TREE VERIFICATION
# ============================================================

$workingTree = (git status --porcelain | Out-String).Trim()

if (-not [string]::IsNullOrWhiteSpace($workingTree)) {
  throw 'REPOSITORY_NOT_CLEAN_AFTER_MUTATION'
}

Write-Host 'Working tree: CLEAN'

# ============================================================
# REMOTE PUSH
# ============================================================

Write-Host '=== REMOTE PUSH ==='

$origin = (git remote get-url origin).Trim()

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) {
  throw 'GIT_ORIGIN_NOT_AVAILABLE'
}

Write-Host "Origin: $origin"
Write-Host 'Push target: origin/main'

git push origin "HEAD:main"

if ($LASTEXITCODE -ne 0) {
  throw 'REPOSITORY_MUTATION_PUSH_FAILED'
}

Write-Host 'Remote push: PASS'

# ============================================================
# REMOTE VERIFICATION
# ============================================================

Write-Host '=== REMOTE VERIFICATION ==='

git fetch origin main --quiet

if ($LASTEXITCODE -ne 0) {
  throw 'REPOSITORY_MUTATION_REMOTE_FETCH_FAILED'
}

$remoteSha = (git rev-parse origin/main).Trim()

if ([string]::IsNullOrWhiteSpace($remoteSha)) {
  throw 'REMOTE_COMMIT_SHA_VERIFICATION_FAILED'
}

Write-Host "Remote Commit SHA: $remoteSha"

if ($remoteSha -ne $commitSha) {
  throw "REPOSITORY_MUTATION_REMOTE_SHA_MISMATCH:local=$commitSha remote=$remoteSha"
}

Write-Host 'Remote commit verification: PASS'

# ============================================================
# FINAL VERIFICATION
# ============================================================

$finalStatus = (git status --porcelain | Out-String).Trim()

if (-not [string]::IsNullOrWhiteSpace($finalStatus)) {
  throw 'REPOSITORY_NOT_CLEAN_AFTER_REMOTE_VERIFICATION'
}

Write-Host 'Final working tree: CLEAN'
Write-Host 'Repository mutation: VERIFIED'
Write-Host 'Remote persistence: VERIFIED'
Write-Host 'Live financial execution: DISABLED'
Write-Host '=== AX REPOSITORY MUTATION GATE COMPLETE ==='

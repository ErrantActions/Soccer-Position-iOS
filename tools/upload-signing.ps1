param(
    [Parameter(Mandatory = $true)][string]$CertificatePath,
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$ApiKeyPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Z0-9]{10}$')][string]$KeyId,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$IssuerId,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Z0-9]{10}$')][string]$TeamId,
    [string]$GhPath = 'gh'
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$repository = 'ErrantActions/Soccer-Position-iOS'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\') + '\'
function Invoke-GhJson([string[]]$Arguments) {
    $result = & $GhPath @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'GitHub request failed. No secrets were uploaded by this request.' }
    return ($result | ConvertFrom-Json)
}
$repo = Invoke-GhJson @('api', "repos/$repository")
if ($repo.private -or $repo.fork) { throw 'Publication approval and an independent public repository are required first.' }
$environment = Invoke-GhJson @('api', "repos/$repository/environments/app-store")
$review = @($environment.protection_rules | Where-Object { $_.type -eq 'required_reviewers' })
if ($review.Count -gt 0 -and ($review.Count -ne 1 -or $review[0].reviewers.Count -ne 1 -or
    $review[0].reviewers[0].type -ne 'User' -or
    $review[0].reviewers[0].reviewer.id -ne 11909244 -or
    $review[0].reviewers[0].reviewer.login -ne 'ErrantActions')) {
    throw 'If reviewer protection is enabled, the sole required reviewer must be the owner ErrantActions.'
}
if ($environment.can_admins_bypass -ne $false) {
    throw 'Admin bypass must be explicitly disabled before signing secrets are uploaded.'
}
if ($environment.deployment_branch_policy.protected_branches -or -not $environment.deployment_branch_policy.custom_branch_policies) {
    throw 'Expected an explicit main-only deployment branch policy.'
}
$policies = Invoke-GhJson @('api', "repos/$repository/environments/app-store/deployment-branch-policies")
if ($policies.branch_policies.Count -ne 1 -or $policies.branch_policies[0].name -ne 'main' -or $policies.branch_policies[0].type -ne 'branch') {
    throw 'Environment must allow only the main branch.'
}
foreach ($path in @($CertificatePath, $ProfilePath, $ApiKeyPath)) {
    $resolved = (Resolve-Path -LiteralPath $path).Path
    if ($resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Keep all signing files outside the repository, even when ignored.'
    }
}
function Set-EnvironmentSecret([string]$Name, [string]$Value) {
    $Value | & $GhPath secret set $Name --repo $repository --env app-store
    if ($LASTEXITCODE -ne 0) { throw "Upload of $Name failed. Earlier secrets may already have been updated; rerun after resolving the error." }
}
$password = Read-Host 'Distribution .p12 password (masked; never enter it in chat)' -AsSecureString
$pointer = [IntPtr]::Zero
try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    Set-EnvironmentSecret 'DISTRIBUTION_CERTIFICATE_BASE64' ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $CertificatePath).Path)))
    Set-EnvironmentSecret 'DISTRIBUTION_CERTIFICATE_PASSWORD' ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer))
    Set-EnvironmentSecret 'PROVISIONING_PROFILE_BASE64' ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ProfilePath).Path)))
    Set-EnvironmentSecret 'APP_STORE_CONNECT_KEY_ID' $KeyId
    Set-EnvironmentSecret 'APP_STORE_CONNECT_ISSUER_ID' $IssuerId
    Set-EnvironmentSecret 'APP_STORE_CONNECT_PRIVATE_KEY' ([IO.File]::ReadAllText((Resolve-Path -LiteralPath $ApiKeyPath).Path))
    & $GhPath variable set APPLE_TEAM_ID --body $TeamId --repo $repository --env app-store
    if ($LASTEXITCODE -ne 0) { throw 'Failed to save the team variable; secrets were uploaded but releases remain blocked.' }
    Write-Output 'Signing secrets uploaded to the existing protected environment. Its protection rules were not modified.'
} finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    $password.Dispose()
}

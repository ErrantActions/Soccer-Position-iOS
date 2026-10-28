$ErrorActionPreference = 'Stop'
$global:CoachAITestReviewers = @(
    @{type='User'; reviewer=@{id=11909244; login='ErrantActions'}}
)
$global:CoachAITestAdminsBypass = $false
function Invoke-FakeGh {
    $global:LASTEXITCODE = 0
    if ($args[1] -eq 'repos/ErrantActions/Soccer-Position-iOS') {
        return (@{private=$false; fork=$false} | ConvertTo-Json)
    }
    if ($args[1] -eq 'repos/ErrantActions/Soccer-Position-iOS/environments/app-store') {
        return (@{
            protection_rules=@(@{type='required_reviewers'; reviewers=$global:CoachAITestReviewers})
            can_admins_bypass=$global:CoachAITestAdminsBypass
            deployment_branch_policy=@{protected_branches=$false; custom_branch_policies=$true}
        } | ConvertTo-Json -Depth 6)
    }
    throw 'Unexpected GitHub request; tests must never upload a secret.'
}
function Assert-UploadRejected([string]$Expected) {
    try {
        & (Join-Path $PSScriptRoot '..\upload-signing.ps1') `
            -CertificatePath 'not-used.p12' -ProfilePath 'not-used.mobileprovision' `
            -ApiKeyPath 'not-used.p8' -KeyId TESTKEY001 `
            -IssuerId 11111111-1111-1111-1111-111111111111 -TeamId TESTTEAM01 `
            -GhPath Invoke-FakeGh
        throw 'Expected the signing upload to be rejected.'
    } catch {
        if ($_.Exception.Message -notlike "*$Expected*") { throw }
    }
}
$global:CoachAITestAdminsBypass = $true
Assert-UploadRejected 'Admin bypass must be explicitly disabled'
$global:CoachAITestAdminsBypass = $false
$global:CoachAITestReviewers += @{type='User'; reviewer=@{id=2; login='AnotherReviewer'}}
Assert-UploadRejected 'sole required reviewer'
Write-Output 'Signing upload guards passed: owner-only review and no admin bypass.'
Remove-Variable CoachAITestReviewers, CoachAITestAdminsBypass -Scope Global

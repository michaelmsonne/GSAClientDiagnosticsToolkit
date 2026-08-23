BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAForwardingProfileAssignment' {
    It 'fails when the tenant is not onboarded' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-GSACurrentUserUPN { 'user@contoso.com' }
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ onboardingStatus = 'notOnboarded' } }
            Test-GSAForwardingProfileAssignment -AccessToken 'token' -ProfileType private -PassThru | Should -Be $false
        }
    }

    It 'fails when the forwarding profile is not enabled' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-GSACurrentUserUPN { 'user@contoso.com' }
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'tenantStatus') { return [PSCustomObject]@{ onboardingStatus = 'onboarded' } }
                if ($Uri -match 'forwardingProfiles') { return [PSCustomObject]@{ value = @([PSCustomObject]@{ state = 'disabled'; servicePrincipal = [PSCustomObject]@{ id = 'sp-1' } }) } }
            }
            Test-GSAForwardingProfileAssignment -AccessToken 'token' -ProfileType private -PassThru | Should -Be $false
        }
    }

    It 'passes when onboarded, enabled, and assignment is not required' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-GSACurrentUserUPN { 'user@contoso.com' }
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'tenantStatus') { return [PSCustomObject]@{ onboardingStatus = 'onboarded' } }
                if ($Uri -match 'forwardingProfiles') { return [PSCustomObject]@{ value = @([PSCustomObject]@{ state = 'enabled'; servicePrincipal = [PSCustomObject]@{ id = 'sp-1' } }) } }
                if ($Uri -match 'servicePrincipals') { return [PSCustomObject]@{ appRoleAssignmentRequired = $false; appRoleAssignedTo = @() } }
            }
            Test-GSAForwardingProfileAssignment -AccessToken 'token' -ProfileType private -PassThru | Should -Be $true
        }
    }

    It 'fails when no UPN can be determined' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-GSACurrentUserUPN { $null }
            Test-GSAForwardingProfileAssignment -AccessToken 'token' -ProfileType private -PassThru | Should -Be $false
        }
    }
}

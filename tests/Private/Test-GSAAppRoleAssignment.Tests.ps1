BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAAppRoleAssignment' {
    It 'returns $true when assignment is not required' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Test-GSAAppRoleAssignment -AccessToken 'token' -UserPrincipalName 'user@contoso.com' -AssignmentRequired $false -AssignedUsers @() -AssignedGroupIds @() | Should -Be $true
        }
    }

    It 'returns $true when the user is directly assigned' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ id = 'user-1' } }
            $assignedUsers = @([PSCustomObject]@{ principalId = 'user-1' })
            Test-GSAAppRoleAssignment -AccessToken 'token' -UserPrincipalName 'user@contoso.com' -AssignmentRequired $true -AssignedUsers $assignedUsers -AssignedGroupIds @() | Should -Be $true
        }
    }

    It 'returns $false when the user cannot be resolved' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { $null }
            Test-GSAAppRoleAssignment -AccessToken 'token' -UserPrincipalName 'user@contoso.com' -AssignmentRequired $true -AssignedUsers @() -AssignedGroupIds @() | Should -Be $false
        }
    }

    It 'returns $true when the user is a member of an assigned group' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'checkMemberGroups') { return [PSCustomObject]@{ value = @('group-1') } }
                [PSCustomObject]@{ id = 'user-1' }
            }
            Test-GSAAppRoleAssignment -AccessToken 'token' -UserPrincipalName 'user@contoso.com' -AssignmentRequired $true -AssignedUsers @() -AssignedGroupIds @('group-1') | Should -Be $true
        }
    }

    It 'returns $false when the user is not directly assigned and has no assigned groups' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ id = 'user-1' } }
            Test-GSAAppRoleAssignment -AccessToken 'token' -UserPrincipalName 'user@contoso.com' -AssignmentRequired $true -AssignedUsers @() -AssignedGroupIds @() | Should -Be $false
        }
    }

    It 'returns $false when group membership check returns no matches' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'checkMemberGroups') { return [PSCustomObject]@{ value = @() } }
                [PSCustomObject]@{ id = 'user-1' }
            }
            Test-GSAAppRoleAssignment -AccessToken 'token' -UserPrincipalName 'user@contoso.com' -AssignmentRequired $true -AssignedUsers @() -AssignedGroupIds @('group-1') | Should -Be $false
        }
    }
}

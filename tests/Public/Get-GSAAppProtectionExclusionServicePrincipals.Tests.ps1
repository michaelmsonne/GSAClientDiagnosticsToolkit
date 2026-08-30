BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Get-GSAAppProtectionExclusionServicePrincipals' {
    It 'returns all known Global Secure Access exclusion service principals' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                [PSCustomObject]@{
                    value = @([PSCustomObject]@{
                        id = 'sp-id-1'
                        appId = 'cde6adac-58fd-4b78-8d6d-9beaf1b0d668'
                        displayName = 'Global Secure Access Client'
                        accountEnabled = $true
                        servicePrincipalType = 'Application'
                    })
                }
            }

            $result = Get-GSAAppProtectionExclusionServicePrincipals -PassThru

            $result | Should -HaveCount 8
            ($result | Select-Object -ExpandProperty AppId) | Should -Contain 'cde6adac-58fd-4b78-8d6d-9beaf1b0d668'
            ($result | Select-Object -ExpandProperty AppId) | Should -Contain '5dc48733-b5df-475c-a49b-fa307ef00853'
            ($result | Select-Object -ExpandProperty AppId) | Should -Contain 'c08f52c9-8f03-4558-a0ea-9a4c878cf343'
            ($result | Select-Object -ExpandProperty AppId) | Should -Contain 'b3fa0115-39b3-4bec-8cc6-8c4fcd33e69d'
            ($result | Select-Object -ExpandProperty AppId) | Should -Contain 'ca01d00c-bfd6-46d6-ae7d-be5b5267d037'
            ($result | Select-Object -ExpandProperty AppId) | Should -Contain '3b80cd3f-61ca-49b0-8d0f-7b6760e08705'
            ($result | Select-Object -ExpandProperty AppId) | Should -Contain 'e92b9b37-1b47-4c01-9fbc-91d84450870e'
            ($result | Select-Object -ExpandProperty AppId) | Should -Contain '7dd7250c-c317-4bc6-8528-8d27b02707ef'
        }
    }

    It 'supports returning hashtable entries' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ value = @() } }
            $result = Get-GSAAppProtectionExclusionServicePrincipals -AsHashtable

            $result | Should -HaveCount 8
            $result[0].GetType().Name | Should -Be 'Hashtable'
        }
    }

    It 'reports Missing state when a service principal is not found' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ value = @() } }

            $result = Get-GSAAppProtectionExclusionServicePrincipals -PassThru

            ($result | Where-Object { $_.AppId -eq 'cde6adac-58fd-4b78-8d6d-9beaf1b0d668' }).ExistsInTenant | Should -Be $false
            ($result | Where-Object { $_.AppId -eq 'cde6adac-58fd-4b78-8d6d-9beaf1b0d668' }).CurrentState | Should -Be 'Missing'
        }
    }

    It 'supports static mode without tenant validation' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { throw 'Should not be called when validation is disabled.' }

            $result = Get-GSAAppProtectionExclusionServicePrincipals -ValidateInTenant:$false -PassThru

            $result | Should -HaveCount 8
            ($result | Select-Object -First 1).CurrentState | Should -Be 'NotValidated'
            ($result | Select-Object -First 1).ExistsInTenant | Should -Be $null
        }
    }

    It 'reads accountEnabled from a Hashtable Graph response (SDK session shape)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                @{
                    value = @(
                        @{
                            id = 'sp-id-1'
                            appId = 'cde6adac-58fd-4b78-8d6d-9beaf1b0d668'
                            displayName = 'Global Secure Access Client'
                            accountEnabled = $true
                            servicePrincipalType = 'Application'
                        }
                    )
                }
            }

            $result = Get-GSAAppProtectionExclusionServicePrincipals -PassThru
            $first = $result | Where-Object { $_.AppId -eq 'cde6adac-58fd-4b78-8d6d-9beaf1b0d668' }

            $first.ExistsInTenant | Should -Be $true
            $first.CurrentState | Should -Be 'Enabled'
        }
    }
}
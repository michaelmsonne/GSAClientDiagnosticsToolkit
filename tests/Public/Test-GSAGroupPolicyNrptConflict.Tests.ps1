BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAGroupPolicyNrptConflict' {
    It 'passes when no Group Policy NRPT key exists' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $false }
            Test-GSAGroupPolicyNrptConflict -PassThru | Should -Be $true
        }
    }

    It 'fails when the Group Policy NRPT key exists with an empty rule list' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $true }
            Mock Get-ChildItem { @() }
            Test-GSAGroupPolicyNrptConflict -PassThru | Should -Be $false
        }
    }

    It 'fails when the Group Policy NRPT key exists with rules' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $true }
            Mock Get-ChildItem { @([PSCustomObject]@{ PSChildName = 'rule1' }) }
            Test-GSAGroupPolicyNrptConflict -PassThru | Should -Be $false
        }
    }

    It 'returns nothing by default (no -PassThru)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $false }
            Test-GSAGroupPolicyNrptConflict | Should -BeNullOrEmpty
        }
    }

    It 'does not prompt or search SYSVOL when no conflict is found, even with -FindSourceGpo' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $false }
            Mock Read-Host
            Test-GSAGroupPolicyNrptConflict -FindSourceGpo -PassThru | Should -Be $true
            Should -Invoke Read-Host -Times 0
        }
    }

    It '-FindSourceGpo auto-detects the domain and searches SYSVOL for matching GPOs when confirmed' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $true } -ParameterFilter { $Path -like 'HKLM:*' }
            Mock Get-ChildItem { @([PSCustomObject]@{ PSChildName = 'rule1' }) } -ParameterFilter { -not $Recurse }
            Mock Get-CimInstance { [PSCustomObject]@{ PartOfDomain = $true; Domain = 'contoso.com' } }
            Mock Read-Host { '' }
            Mock Get-ChildItem {
                @([PSCustomObject]@{ FullName = '\\contoso.com\SYSVOL\contoso.com\Policies\{guid}\Machine\registry.pol' })
            } -ParameterFilter { $Recurse }
            Mock Get-Content { @('some', 'dnspolicyconfig', 'data') }

            Test-GSAGroupPolicyNrptConflict -FindSourceGpo -PassThru | Should -Be $false
            Should -Invoke Get-ChildItem -ParameterFilter { $Recurse } -Times 1
        }
    }

    It '-FindSourceGpo skips the SYSVOL search when the user provides a blank path and no domain is detected' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $true } -ParameterFilter { $Path -like 'HKLM:*' }
            Mock Get-ChildItem { @() } -ParameterFilter { -not $Recurse }
            Mock Get-CimInstance { [PSCustomObject]@{ PartOfDomain = $false; Domain = $null } }
            Mock Read-Host { '' }

            Test-GSAGroupPolicyNrptConflict -FindSourceGpo -PassThru | Should -Be $false
            Should -Invoke Get-ChildItem -ParameterFilter { $Recurse } -Times 0
        }
    }
}

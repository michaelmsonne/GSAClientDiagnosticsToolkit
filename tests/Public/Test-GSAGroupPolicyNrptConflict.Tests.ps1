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
}

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAForwardingProfileRegistry' {
    It 'fails when the registry key does not exist' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemProperty { $null }
            Test-GSAForwardingProfileRegistry | Should -Be $false
        }
    }

    It 'fails when the registry value is empty' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemProperty { [PSCustomObject]@{ ForwardingProfile = '' } }
            Mock Get-ItemPropertyValue { '' }
            Test-GSAForwardingProfileRegistry | Should -Be $false
        }
    }

    It 'fails when the profile value is not valid JSON' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemProperty { [PSCustomObject]@{ ForwardingProfile = 'not-json' } }
            Mock Get-ItemPropertyValue { 'not-json' }
            Test-GSAForwardingProfileRegistry | Should -Be $false
        }
    }

    It 'fails when the profile JSON has no channels configured' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"channels":[]}}'
            Mock Get-ItemProperty { [PSCustomObject]@{ ForwardingProfile = $json } }
            Mock Get-ItemPropertyValue { $json }
            Test-GSAForwardingProfileRegistry | Should -Be $false
        }
    }

    It 'passes when the profile JSON contains at least one channel' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"channels":[{"name":"M365","diagnosticUri":"https://diag.example.com"}]}}'
            Mock Get-ItemProperty { [PSCustomObject]@{ ForwardingProfile = $json } }
            Mock Get-ItemPropertyValue { $json }
            Test-GSAForwardingProfileRegistry | Should -Be $true
        }
    }
}

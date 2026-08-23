BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Get-JsonFromRegistry' {
    It 'returns parsed JSON when the registry value exists' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { '{"policy":{"channels":[]}}' }
            $result = Get-JsonFromRegistry -ValueName 'ForwardingProfile'
            $result.policy.channels.Count | Should -Be 0
        }
    }

    It 'returns $null when the registry value is empty' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { $null }
            $result = Get-JsonFromRegistry -ValueName 'ForwardingProfile'
            $result | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the registry read throws' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { throw 'Registry access denied' }
            $result = Get-JsonFromRegistry -ValueName 'ForwardingProfile'
            $result | Should -BeNullOrEmpty
        }
    }
}

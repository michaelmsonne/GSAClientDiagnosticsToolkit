BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAHyperVExternalSwitch' {
    It 'returns nothing by default (no -PassThru)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { @() }
            Test-GSAHyperVExternalSwitch | Should -BeNullOrEmpty
        }
    }

    It 'passes when no Hyper-V external virtual switch is found' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { @() }
            Test-GSAHyperVExternalSwitch -PassThru | Should -Be $true
        }
    }

    It 'passes when Hyper-V is not installed/available on this host' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { throw 'The term ''Get-VMSwitch'' is not recognized...' }
            Test-GSAHyperVExternalSwitch -PassThru | Should -Be $true
        }
    }

    It 'reports a warning (still passes) when a Hyper-V external virtual switch is found' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { @([PSCustomObject]@{ Name = 'ExternalSwitch'; SwitchType = 'External'; NetAdapterInterfaceDescription = 'Ethernet Adapter' }) }
            $result = Test-GSAHyperVExternalSwitch -PassThru
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 1
        }
    }

    It 'queries Get-VMSwitch with -SwitchType External' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { @() }
            Test-GSAHyperVExternalSwitch -PassThru | Out-Null
            Should -Invoke Get-VMSwitch -ParameterFilter { $SwitchType -eq 'External' }
        }
    }
}

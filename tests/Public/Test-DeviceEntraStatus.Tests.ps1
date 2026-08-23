BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-DeviceEntraStatus' {
    It 'passes when the device is Entra joined and Private Access is enabled' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock dsregcmd { @('AzureAdJoined : YES') }
            Mock Get-ItemProperty { [PSCustomObject]@{ IsPrivateAccessDisabledByUser = 0 } }
            Test-DeviceEntraStatus | Should -Be $true
        }
    }

    It 'fails when the device is not Entra joined' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock dsregcmd { @('AzureAdJoined : NO') }
            Mock Get-ItemProperty { $null }
            Test-DeviceEntraStatus | Should -Be $false
        }
    }

    It 'still passes (with a logged warning) when Private Access is user-disabled' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock dsregcmd { @('AzureAdJoined : YES') }
            Mock Get-ItemProperty { [PSCustomObject]@{ IsPrivateAccessDisabledByUser = 1 } }
            Test-DeviceEntraStatus | Should -Be $true
        }
    }

    It 'fails when dsregcmd throws' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock dsregcmd { throw 'command not found' }
            Mock Get-ItemProperty { [PSCustomObject]@{ IsPrivateAccessDisabledByUser = 0 } }
            Test-DeviceEntraStatus | Should -Be $false
        }
    }
}

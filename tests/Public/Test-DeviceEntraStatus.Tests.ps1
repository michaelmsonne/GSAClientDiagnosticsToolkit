BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Test-DeviceEntraStatus' {
    It 'passes when the device is Entra joined and Private Access is enabled' {
        InModuleScope GSAClientConnectivityChecker {
            Mock dsregcmd { @('AzureAdJoined : YES') }
            Mock Get-ItemProperty { [PSCustomObject]@{ IsPrivateAccessDisabledByUser = 0 } }
            Test-DeviceEntraStatus | Should -Be $true
        }
    }

    It 'fails when the device is not Entra joined' {
        InModuleScope GSAClientConnectivityChecker {
            Mock dsregcmd { @('AzureAdJoined : NO') }
            Mock Get-ItemProperty { $null }
            Test-DeviceEntraStatus | Should -Be $false
        }
    }

    It 'still passes (with a logged warning) when Private Access is user-disabled' {
        InModuleScope GSAClientConnectivityChecker {
            Mock dsregcmd { @('AzureAdJoined : YES') }
            Mock Get-ItemProperty { [PSCustomObject]@{ IsPrivateAccessDisabledByUser = 1 } }
            Test-DeviceEntraStatus | Should -Be $true
        }
    }

    It 'fails when dsregcmd throws' {
        InModuleScope GSAClientConnectivityChecker {
            Mock dsregcmd { throw 'command not found' }
            Mock Get-ItemProperty { [PSCustomObject]@{ IsPrivateAccessDisabledByUser = 0 } }
            Test-DeviceEntraStatus | Should -Be $false
        }
    }
}

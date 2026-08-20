BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAIPv6Status' {
    It 'reports a warning when no active physical adapters are found' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-NetAdapter { @() }
            $result = Test-GSAIPv6Status
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 1
        }
    }

    It 'passes when IPv6 is disabled on all active physical adapters' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-NetAdapter { @([PSCustomObject]@{ Name = 'Ethernet'; Status = 'Up'; Virtual = $false }) }
            Mock Get-NetAdapterBinding { [PSCustomObject]@{ Enabled = $false } }
            Test-GSAIPv6Status | Should -Be $true
        }
    }

    It 'reports a warning when IPv6 is enabled on an adapter' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-NetAdapter { @([PSCustomObject]@{ Name = 'Ethernet'; Status = 'Up'; Virtual = $false }) }
            Mock Get-NetAdapterBinding { [PSCustomObject]@{ Enabled = $true } }
            $result = Test-GSAIPv6Status
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 1
        }
    }

    It 'fails when adapter enumeration throws' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-NetAdapter { throw 'WMI error' }
            Test-GSAIPv6Status | Should -Be $false
        }
    }
}

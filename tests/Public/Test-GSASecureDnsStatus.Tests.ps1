BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSASecureDnsStatus' {
    It 'reports success when DoH is not enforced for either browser' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-ItemProperty { $null }
            Test-GSASecureDnsStatus | Should -Be $true
        }
    }

    It 'still returns $true even when DoH is enabled (warning-only check)' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-ItemProperty { [PSCustomObject]@{ DnsOverHttpsMode = 'automatic' } }
            Test-GSASecureDnsStatus | Should -Be $true
        }
    }
}

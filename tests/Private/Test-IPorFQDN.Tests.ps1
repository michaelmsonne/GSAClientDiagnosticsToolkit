BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Test-IPorFQDN' {
    It 'identifies a valid IPv4 address' {
        InModuleScope GSAClientConnectivityChecker {
            Test-IPorFQDN -FQDNorIP '10.0.0.1' | Should -Be 'IP'
        }
    }

    It 'identifies a valid FQDN' {
        InModuleScope GSAClientConnectivityChecker {
            Test-IPorFQDN -FQDNorIP 'fileserver.contoso.com' | Should -Be 'FQDN'
        }
    }

    It 'returns $null for an out-of-range IPv4 octet' {
        InModuleScope GSAClientConnectivityChecker {
            Test-IPorFQDN -FQDNorIP '999.0.0.1' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for an invalid string' {
        InModuleScope GSAClientConnectivityChecker {
            Test-IPorFQDN -FQDNorIP 'not a host' | Should -BeNullOrEmpty
        }
    }
}

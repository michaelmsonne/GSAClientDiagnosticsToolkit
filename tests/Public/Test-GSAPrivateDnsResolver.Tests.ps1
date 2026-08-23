BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAPrivateDnsResolver' {
    It 'passes when the resolver responds successfully' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Resolve-DnsName { }
            Test-GSAPrivateDnsResolver | Should -Be $true
        }
    }

    It 'passes when the resolver returns an NXDOMAIN-style error (still a response)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Resolve-DnsName { throw 'DNS name does not exist' }
            Test-GSAPrivateDnsResolver | Should -Be $true
        }
    }

    It 'fails when the resolver is unreachable' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Resolve-DnsName { throw 'A connection attempt failed because the connected party did not properly respond' }
            Test-GSAPrivateDnsResolver | Should -Be $false
        }
    }
}

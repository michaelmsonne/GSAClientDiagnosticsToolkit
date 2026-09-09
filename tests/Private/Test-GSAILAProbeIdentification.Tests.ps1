BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAILAProbeIdentification' {
    It 'returns $true when the FQDN is not publicly resolvable and addresses are private' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 3; Answer = @() } }
            Test-GSAILAProbeIdentification -ContextLabel 'Test' -FQDN internal.contoso.local -ServerAddresses '192.168.1.1' -ExpectedIPs '192.168.1.1' -PublicDnsServer 'https://dns.google/resolve' | Should -Be $true
        }
    }

    It 'returns $false when the FQDN is publicly resolvable' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 0; Answer = @([PSCustomObject]@{ type = 1; data = '20.10.30.40' }) } }
            Test-GSAILAProbeIdentification -ContextLabel 'Test' -FQDN public.contoso.com -PublicDnsServer 'https://dns.google/resolve' | Should -Be $false
        }
    }

    It 'returns $true (inconclusive) when the resolved address is a GSA synthetic 6.6.x.x address' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 0; Answer = @([PSCustomObject]@{ type = 1; data = '6.6.6.57' }) } }
            Test-GSAILAProbeIdentification -ContextLabel 'Test' -FQDN unifi.home.contoso.com -PublicDnsServer 'https://dns.google/resolve' | Should -Be $true
        }
    }

    It 'returns $false when a DNS server address is public' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 3; Answer = @() } }
            Test-GSAILAProbeIdentification -ContextLabel 'Test' -FQDN internal.contoso.local -ServerAddresses '20.10.30.1' -PublicDnsServer 'https://dns.google/resolve' | Should -Be $false
        }
    }

    It 'returns $true (warns only) when an expected IP resolution is public' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 3; Answer = @() } }
            Test-GSAILAProbeIdentification -ContextLabel 'Test' -FQDN internal.contoso.local -ServerAddresses '192.168.1.1' -ExpectedIPs '80.209.114.79' -PublicDnsServer 'https://dns.google/resolve' | Should -Be $true
        }
    }
}

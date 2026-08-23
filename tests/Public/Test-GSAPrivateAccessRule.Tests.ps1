BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAPrivateAccessRule' {
    It 'fails when the target is not a valid FQDN or IP' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Test-GSAPrivateAccessRule -FQDNorIP 'not a host' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'fails when the registry configuration cannot be loaded' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { $null }
            Test-GSAPrivateAccessRule -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'fails when the forwarding profile has no rules' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { '{"policy":{"rules":[]}}' }
            Test-GSAPrivateAccessRule -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'fails when no rule covers the target address' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"rules":[{"id":"rule-1","appAuthorizationTokenContext":{"audienceScope":"api://11111111-1111-1111-1111-111111111111/.default"},"matchingCriteria":{"address":{"fqdns":["other\\.contoso\\.com"]},"ports":[{"start":445,"end":445}],"protocol":"TCP"}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Test-GSAPrivateAccessRule -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'fails when the address matches but the port does not' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"rules":[{"id":"rule-1","appAuthorizationTokenContext":{"audienceScope":"api://11111111-1111-1111-1111-111111111111/.default"},"matchingCriteria":{"address":{"fqdns":["fileserver\\.contoso\\.com"]},"ports":[{"start":80,"end":80}],"protocol":"TCP"}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Test-GSAPrivateAccessRule -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'fails when the address and port match but the protocol does not' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"rules":[{"id":"rule-1","appAuthorizationTokenContext":{"audienceScope":"api://11111111-1111-1111-1111-111111111111/.default"},"matchingCriteria":{"address":{"fqdns":["fileserver\\.contoso\\.com"]},"ports":[{"start":445,"end":445}],"protocol":"UDP"}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Test-GSAPrivateAccessRule -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'passes when address, port, and protocol all match' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"rules":[{"id":"rule-1","appAuthorizationTokenContext":{"audienceScope":"api://11111111-1111-1111-1111-111111111111/.default"},"matchingCriteria":{"address":{"fqdns":["fileserver\\.contoso\\.com"]},"ports":[{"start":445,"end":445}],"protocol":"TCP"}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Test-GSAPrivateAccessRule -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $true
        }
    }

    It 'passes when the rule protocol is All' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"rules":[{"id":"rule-1","appAuthorizationTokenContext":{"audienceScope":"api://11111111-1111-1111-1111-111111111111/.default"},"matchingCriteria":{"address":{"ips":[{"start":167772160,"end":167772415}]},"ports":[{"start":3389,"end":3389}],"protocol":"All"}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Test-GSAPrivateAccessRule -FQDNorIP '10.0.0.42' -Port 3389 -Protocol UDP -PassThru | Should -Be $true
        }
    }

    It 'returns nothing when -PassThru is not specified' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"rules":[{"id":"rule-1","appAuthorizationTokenContext":{"audienceScope":"api://11111111-1111-1111-1111-111111111111/.default"},"matchingCriteria":{"address":{"fqdns":["fileserver\\.contoso\\.com"]},"ports":[{"start":445,"end":445}],"protocol":"TCP"}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Test-GSAPrivateAccessRule -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP | Should -BeNullOrEmpty
        }
    }
}

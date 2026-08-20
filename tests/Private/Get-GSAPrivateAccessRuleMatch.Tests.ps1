BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Get-GSAPrivateAccessRuleMatch' {
    It 'matches an FQDN rule on address, port, and protocol' {
        InModuleScope GSAClientConnectivityChecker {
            $rules = @(
                [PSCustomObject]@{
                    id                          = 'rule-1'
                    appAuthorizationTokenContext = [PSCustomObject]@{ audienceScope = 'api://11111111-1111-1111-1111-111111111111/.default' }
                    matchingCriteria            = [PSCustomObject]@{
                        address  = [PSCustomObject]@{ fqdns = @('fileserver\.contoso\.com') }
                        ports    = @([PSCustomObject]@{ start = 445; end = 445 })
                        protocol = 'TCP'
                    }
                }
            )

            $result = Get-GSAPrivateAccessRuleMatch -Rules $rules -FQDNorIP 'fileserver.contoso.com' -InputType 'FQDN' -Port 445 -Protocol 'TCP'

            $result.AddressMatched | Should -Be $true
            $result.PortMatched | Should -Be $true
            $result.ProtocolMatched | Should -Be $true
            $result.RuleId | Should -Be 'rule-1'
            $result.AppId | Should -Be '11111111-1111-1111-1111-111111111111'
        }
    }

    It 'matches address but not port when the port is out of range' {
        InModuleScope GSAClientConnectivityChecker {
            $rules = @(
                [PSCustomObject]@{
                    id                          = 'rule-1'
                    appAuthorizationTokenContext = [PSCustomObject]@{ audienceScope = 'api://11111111-1111-1111-1111-111111111111/.default' }
                    matchingCriteria            = [PSCustomObject]@{
                        address  = [PSCustomObject]@{ fqdns = @('fileserver\.contoso\.com') }
                        ports    = @([PSCustomObject]@{ start = 80; end = 80 })
                        protocol = 'TCP'
                    }
                }
            )

            $result = Get-GSAPrivateAccessRuleMatch -Rules $rules -FQDNorIP 'fileserver.contoso.com' -InputType 'FQDN' -Port 445 -Protocol 'TCP'

            $result.AddressMatched | Should -Be $true
            $result.PortMatched | Should -Be $false
            $result.ProtocolMatched | Should -Be $false
        }
    }

    It 'matches an IP-based rule using decimal address ranges' {
        InModuleScope GSAClientConnectivityChecker {
            $rules = @(
                [PSCustomObject]@{
                    id                          = 'rule-2'
                    appAuthorizationTokenContext = [PSCustomObject]@{ audienceScope = 'api://22222222-2222-2222-2222-222222222222/.default' }
                    matchingCriteria            = [PSCustomObject]@{
                        address  = [PSCustomObject]@{ ips = @([PSCustomObject]@{ start = 167772160; end = 167772415 }) }
                        ports    = @([PSCustomObject]@{ start = 3389; end = 3389 })
                        protocol = 'All'
                    }
                }
            )

            $result = Get-GSAPrivateAccessRuleMatch -Rules $rules -FQDNorIP '10.0.0.42' -InputType 'IP' -Port 3389 -Protocol 'UDP'

            $result.AddressMatched | Should -Be $true
            $result.PortMatched | Should -Be $true
            $result.ProtocolMatched | Should -Be $true
            $result.AppId | Should -Be '22222222-2222-2222-2222-222222222222'
        }
    }

    It 'reports no match when no rule covers the address' {
        InModuleScope GSAClientConnectivityChecker {
            $rules = @(
                [PSCustomObject]@{
                    id                          = 'rule-1'
                    appAuthorizationTokenContext = [PSCustomObject]@{ audienceScope = 'api://11111111-1111-1111-1111-111111111111/.default' }
                    matchingCriteria            = [PSCustomObject]@{
                        address  = [PSCustomObject]@{ fqdns = @('other\.contoso\.com') }
                        ports    = @([PSCustomObject]@{ start = 445; end = 445 })
                        protocol = 'TCP'
                    }
                }
            )

            $result = Get-GSAPrivateAccessRuleMatch -Rules $rules -FQDNorIP 'fileserver.contoso.com' -InputType 'FQDN' -Port 445 -Protocol 'TCP'

            $result.AddressMatched | Should -Be $false
            $result.RuleId | Should -BeNullOrEmpty
        }
    }
}

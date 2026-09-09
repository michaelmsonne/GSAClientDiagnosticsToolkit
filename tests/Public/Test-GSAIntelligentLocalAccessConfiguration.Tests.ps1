BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAIntelligentLocalAccessConfiguration' {
    It 'passes when there are no Private Networks configured' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ value = @() } }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $true
        }
    }

    It 'fails when a private network has no network identification' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'privateNetworks') { return [PSCustomObject]@{ value = @([PSCustomObject]@{ name = 'Contoso Corp'; appIds = @(); networkIdentifications = @() }) } }
                return [PSCustomObject]@{ value = @() }
            }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $false
        }
    }

    It 'fails when the probe FQDN is publicly resolvable' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'privateNetworks') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{
                            name                    = 'Contoso Corp'
                            appIds                  = @('app-1')
                            networkIdentifications = @([PSCustomObject]@{
                                serverAddresses       = @([PSCustomObject]@{ value = '192.168.1.1' })
                                fqdnToResolve         = [PSCustomObject]@{ value = 'public.contoso.com' }
                                expectedIpResolutions = @([PSCustomObject]@{ value = '192.168.1.1' })
                            })
                        })
                    }
                }
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ appId = 'app-1'; displayName = 'FileServer App' }) }
            }
            Mock Resolve-DnsName { [PSCustomObject]@{ Type = 'A'; IPAddress = '20.10.30.40' } }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $false
        }
    }

    It 'fails when the probe DNS server address is public' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'privateNetworks') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{
                            name                    = 'Contoso Corp'
                            appIds                  = @('app-1')
                            networkIdentifications = @([PSCustomObject]@{
                                serverAddresses       = @([PSCustomObject]@{ value = '20.10.30.1' })
                                fqdnToResolve         = [PSCustomObject]@{ value = 'internal.contoso.local' }
                                expectedIpResolutions = @([PSCustomObject]@{ value = '192.168.1.1' })
                            })
                        })
                    }
                }
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ appId = 'app-1'; displayName = 'FileServer App' }) }
            }
            Mock Resolve-DnsName { throw 'DNS name does not exist' }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $false
        }
    }

    It 'passes when the probe FQDN is not publicly resolvable and addresses are private' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'privateNetworks') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{
                            name                    = 'Contoso Corp'
                            appIds                  = @('app-1')
                            networkIdentifications = @([PSCustomObject]@{
                                serverAddresses       = @([PSCustomObject]@{ value = '192.168.1.1' })
                                fqdnToResolve         = [PSCustomObject]@{ value = 'internal.contoso.local' }
                                expectedIpResolutions = @([PSCustomObject]@{ value = '192.168.1.1' })
                            })
                        })
                    }
                }
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ appId = 'app-1'; displayName = 'FileServer App' }) }
            }
            Mock Resolve-DnsName { throw 'DNS name does not exist' }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $true
        }
    }

    It 'warns but still passes when a Private Network references an App ID that no longer resolves to a known app' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'privateNetworks') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{
                            name                    = 'Contoso Corp'
                            appIds                  = @('stale-app-id')
                            networkIdentifications = @([PSCustomObject]@{
                                serverAddresses       = @([PSCustomObject]@{ value = '192.168.1.1' })
                                fqdnToResolve         = [PSCustomObject]@{ value = 'internal.contoso.local' }
                                expectedIpResolutions = @([PSCustomObject]@{ value = '192.168.1.1' })
                            })
                        })
                    }
                }
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ appId = 'app-1'; displayName = 'FileServer App' }) }
            }
            Mock Resolve-DnsName { throw 'DNS name does not exist' }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $true
        }
    }
}

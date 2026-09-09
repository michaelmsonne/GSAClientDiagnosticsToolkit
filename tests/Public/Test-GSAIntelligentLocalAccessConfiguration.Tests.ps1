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
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 0; Answer = @([PSCustomObject]@{ type = 1; data = '20.10.30.40' }) } }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $false
        }
    }

    It 'passes but does not flag a false failure when the local GSA client intercepts the probe FQDN (synthetic 6.6.x.x answer)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'privateNetworks') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{
                            name                    = 'Home sweet home'
                            appIds                  = @('app-1')
                            networkIdentifications = @([PSCustomObject]@{
                                serverAddresses       = @([PSCustomObject]@{ value = '192.168.1.1' })
                                fqdnToResolve         = [PSCustomObject]@{ value = 'unifi.home.contoso.com' }
                                expectedIpResolutions = @([PSCustomObject]@{ value = '192.168.1.1' })
                            })
                        })
                    }
                }
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ appId = 'app-1'; displayName = 'Home LAN' }) }
            }
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 0; Answer = @([PSCustomObject]@{ type = 1; data = '6.6.6.57' }) } }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $true
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
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 3; Answer = @() } }
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
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 3; Answer = @() } }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $true
        }
    }

    It 'passes when the resolver returns NOERROR with no A record (NODATA, e.g. only an Authority/SOA section)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'privateNetworks') {
                    return [PSCustomObject]@{
                        value = @([PSCustomObject]@{
                            name                    = 'Home sweet home'
                            appIds                  = @('app-1')
                            networkIdentifications = @([PSCustomObject]@{
                                serverAddresses       = @([PSCustomObject]@{ value = '192.168.1.1' })
                                fqdnToResolve         = [PSCustomObject]@{ value = 'unifi.home.contoso.com' }
                                expectedIpResolutions = @([PSCustomObject]@{ value = '192.168.1.1' })
                            })
                        })
                    }
                }
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ appId = 'app-1'; displayName = 'Home LAN' }) }
            }
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 0; Answer = $null } }
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
            Mock Invoke-RestMethod { [PSCustomObject]@{ Status = 3; Answer = @() } }
            Test-GSAIntelligentLocalAccessConfiguration -PassThru | Should -Be $true
        }
    }
}

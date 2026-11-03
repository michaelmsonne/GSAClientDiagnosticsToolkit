BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAHomeNetworkSupport' {
    BeforeEach {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Write-Log {}
            Mock Get-NetAdapter { @([PSCustomObject]@{ Name = 'Ethernet'; Status = 'Up'; ifIndex = 5 }) }
            Mock Get-NetIPAddress { @([PSCustomObject]@{ IPAddress = '192.168.4.69'; PrefixLength = 22 }) }
        }
    }

    It 'fails when the registry configuration cannot be loaded' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-JsonFromRegistry { $null }
            Test-GSAHomeNetworkSupport -PassThru | Should -Be $false
        }
    }

    It 'fails when the Private Access channel was not retrieved' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-JsonFromRegistry { [PSCustomObject]@{ policy = [PSCustomObject]@{ channels = @([PSCustomObject]@{ name = 'M365' }); rules = @() } } }
            Test-GSAHomeNetworkSupport -PassThru | Should -Be $false
        }
    }

    It 'fails when the profile has no localNetwork setting (unsupported client)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-JsonFromRegistry { [PSCustomObject]@{ policy = [PSCustomObject]@{ channels = @([PSCustomObject]@{ name = 'Private'; id = 'p1' }); rules = @() } } }
            Test-GSAHomeNetworkSupport -PassThru | Should -Be $false
            Should -Invoke Write-Log -ParameterFilter { $Message -match 'localNetwork' }
        }
    }

    It 'fails when Allow local subnet bypass is disabled' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-JsonFromRegistry { [PSCustomObject]@{ policy = [PSCustomObject]@{ channels = @([PSCustomObject]@{ name = 'Private'; id = 'p1'; localNetwork = [PSCustomObject]@{ isLocalNetworkFeatureEnabled = $false } }); rules = @() } } }
            Test-GSAHomeNetworkSupport -PassThru | Should -Be $false
            Should -Not -Invoke Get-NetAdapter
        }
    }

    It 'passes when enabled and no Private Access rule overlaps the local subnet' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-JsonFromRegistry { [PSCustomObject]@{ policy = [PSCustomObject]@{
                channels = @([PSCustomObject]@{ name = 'Private'; id = 'p1'; localNetwork = [PSCustomObject]@{ isLocalNetworkFeatureEnabled = $true } })
                rules    = @([PSCustomObject]@{ channelId = 'p1'; action = 'Tunnel'; matchingCriteria = [PSCustomObject]@{ address = [PSCustomObject]@{ ips = @([PSCustomObject]@{ start = 167772160; end = 167837695 }) } } })
            } } }
            Test-GSAHomeNetworkSupport -PassThru | Should -Be $true
            Should -Not -Invoke Write-Log -ParameterFilter { $Level -eq 'WARNING' -and $Message -match 'overlaps' }
        }
    }

    It 'warns when a Private Access IP rule overlaps the local subnet but still passes' {
        InModuleScope GSAClientDiagnosticsToolkit {
            # 192.168.0.0/16 (3232235520..3232301055) contains 192.168.4.0/22
            Mock Get-JsonFromRegistry { [PSCustomObject]@{ policy = [PSCustomObject]@{
                channels = @([PSCustomObject]@{ name = 'Private'; id = 'p1'; localNetwork = [PSCustomObject]@{ isLocalNetworkFeatureEnabled = $true } })
                rules    = @([PSCustomObject]@{ channelId = 'p1'; action = 'Tunnel'; appAuthorizationTokenContext = [PSCustomObject]@{ audienceScope = 'api://app-1/user_impersonation' }; matchingCriteria = [PSCustomObject]@{ address = [PSCustomObject]@{ ips = @([PSCustomObject]@{ start = 3232235520; end = 3232301055 }) } } })
            } } }
            Test-GSAHomeNetworkSupport -PassThru | Should -Be $true
            Should -Invoke Write-Log -ParameterFilter { $Message -match 'overlaps 1 Private Access IP rule' }
        }
    }

    It 'detects overlap with rules using the {f=4; v=<ip>} format and skips IPv6 ranges without errors' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-JsonFromRegistry { [PSCustomObject]@{ policy = [PSCustomObject]@{
                channels = @([PSCustomObject]@{ name = 'Private'; id = 'p1'; localNetwork = [PSCustomObject]@{ isLocalNetworkFeatureEnabled = $true } })
                rules    = @(
                    [PSCustomObject]@{ channelId = 'p1'; action = 'Tunnel'; appAuthorizationTokenContext = [PSCustomObject]@{ audienceScope = 'api://app-2/user_impersonation' }; matchingCriteria = [PSCustomObject]@{ address = [PSCustomObject]@{ ips = @([PSCustomObject]@{ start = [PSCustomObject]@{ f = 4; v = '192.168.4.10' }; end = [PSCustomObject]@{ f = 4; v = '192.168.4.10' } }) } } },
                    [PSCustomObject]@{ channelId = 'p1'; action = 'Tunnel'; matchingCriteria = [PSCustomObject]@{ address = [PSCustomObject]@{ ips = @([PSCustomObject]@{ start = [PSCustomObject]@{ f = 6; v = 'fd00::1' }; end = [PSCustomObject]@{ f = 6; v = 'fd00::2' } }) } } }
                )
            } } }
            Test-GSAHomeNetworkSupport -PassThru -ErrorAction Stop | Should -Be $true
            Should -Invoke Write-Log -ParameterFilter { $Message -match 'overlaps 1 Private Access IP rule.*app-2' }
            Should -Not -Invoke Write-Log -ParameterFilter { $Message -match 'Could not interpret' }
        }
    }

    It 'warns when a Private Access IP range cannot be interpreted' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-JsonFromRegistry { [PSCustomObject]@{ policy = [PSCustomObject]@{
                channels = @([PSCustomObject]@{ name = 'Private'; id = 'p1'; localNetwork = [PSCustomObject]@{ isLocalNetworkFeatureEnabled = $true } })
                rules    = @([PSCustomObject]@{ channelId = 'p1'; action = 'Tunnel'; matchingCriteria = [PSCustomObject]@{ address = [PSCustomObject]@{ ips = @([PSCustomObject]@{ start = [PSCustomObject]@{ f = 4; v = 'garbage' }; end = [PSCustomObject]@{ f = 4; v = 'garbage' } }) } } })
            } } }
            Test-GSAHomeNetworkSupport -PassThru | Should -Be $true
            Should -Invoke Write-Log -ParameterFilter { $Message -match 'Could not interpret 1 Private Access IP range' }
            Should -Not -Invoke Write-Log -ParameterFilter { $Message -match 'No Private Access IP rule overlaps' }
        }
    }

    It 'ignores adapters without an RFC1918 IPv4 address' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-NetIPAddress { @([PSCustomObject]@{ IPAddress = '8.8.4.4'; PrefixLength = 24 }) }
            Mock Get-JsonFromRegistry { [PSCustomObject]@{ policy = [PSCustomObject]@{ channels = @([PSCustomObject]@{ name = 'Private'; id = 'p1'; localNetwork = [PSCustomObject]@{ isLocalNetworkFeatureEnabled = $true } }); rules = @() } } }
            Test-GSAHomeNetworkSupport -PassThru | Should -Be $true
            Should -Invoke Write-Log -ParameterFilter { $Message -match 'No active adapter has an RFC1918' }
        }
    }

    It 'fails when adapter enumeration throws' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-NetAdapter { throw 'WMI error' }
            Mock Get-JsonFromRegistry { [PSCustomObject]@{ policy = [PSCustomObject]@{ channels = @([PSCustomObject]@{ name = 'Private'; id = 'p1'; localNetwork = [PSCustomObject]@{ isLocalNetworkFeatureEnabled = $true } }); rules = @() } } }
            Test-GSAHomeNetworkSupport -PassThru | Should -Be $false
        }
    }
}

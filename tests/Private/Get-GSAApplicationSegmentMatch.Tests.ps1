BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-GSAPortRange' {
    It 'converts start-end strings into objects' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $result = ConvertTo-GSAPortRange -Ranges @('443-443', '1000-2000')
            $result.Count | Should -Be 2
            $result[0].start | Should -Be 443
            $result[0].end | Should -Be 443
            $result[1].start | Should -Be 1000
            $result[1].end | Should -Be 2000
        }
    }

    It 'ignores malformed range strings' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $result = @(ConvertTo-GSAPortRange -Ranges @('not-a-range-1-2', '443-443'))
            $result.Count | Should -Be 1
            $result[0].start | Should -Be 443
        }
    }
}

Describe 'Get-GSAApplicationSegmentMatch' {
    It 'matches an fqdn segment on address, port, and protocol' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $segments = @(
                [PSCustomObject]@{ destinationType = 'fqdn'; destinationHost = 'fileserver.contoso.com'; ports = @('445-445'); protocol = 'tcp' }
            )
            $result = Get-GSAApplicationSegmentMatch -Segments $segments -FQDNorIP 'fileserver.contoso.com' -InputType 'FQDN' -Port 445 -Protocol 'tcp'
            $result.AddressMatched | Should -Be $true
            $result.PortMatched | Should -Be $true
            $result.ProtocolMatched | Should -Be $true
        }
    }

    It 'matches a wildcard fqdn segment' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $segments = @(
                [PSCustomObject]@{ destinationType = 'fqdn'; destinationHost = '*.contoso.com'; ports = @('445-445'); protocol = 'tcp' }
            )
            $result = Get-GSAApplicationSegmentMatch -Segments $segments -FQDNorIP 'fileserver.contoso.com' -InputType 'FQDN' -Port 445 -Protocol 'tcp'
            $result.AddressMatched | Should -Be $true
        }
    }

    It 'matches an ip segment' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $segments = @(
                [PSCustomObject]@{ destinationType = 'ip'; destinationHost = '10.0.0.42'; ports = @('3389-3389'); protocol = 'tcp' }
            )
            $result = Get-GSAApplicationSegmentMatch -Segments $segments -FQDNorIP '10.0.0.42' -InputType 'IP' -Port 3389 -Protocol 'tcp'
            $result.AddressMatched | Should -Be $true
            $result.PortMatched | Should -Be $true
            $result.ProtocolMatched | Should -Be $true
        }
    }

    It 'matches an ipRange segment' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $segments = @(
                [PSCustomObject]@{ destinationType = 'ipRange'; destinationHost = '10.0.0.0..10.0.0.255'; ports = @('445-445'); protocol = 'tcp' }
            )
            $result = Get-GSAApplicationSegmentMatch -Segments $segments -FQDNorIP '10.0.0.42' -InputType 'IP' -Port 445 -Protocol 'tcp'
            $result.AddressMatched | Should -Be $true
        }
    }

    It 'matches an ipRangeCidr segment' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $segments = @(
                [PSCustomObject]@{ destinationType = 'ipRangeCidr'; destinationHost = '10.0.0.0/24'; ports = @('445-445'); protocol = 'tcp' }
            )
            $result = Get-GSAApplicationSegmentMatch -Segments $segments -FQDNorIP '10.0.0.42' -InputType 'IP' -Port 445 -Protocol 'tcp'
            $result.AddressMatched | Should -Be $true
        }
    }

    It 'reports port not matched when out of range' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $segments = @(
                [PSCustomObject]@{ destinationType = 'fqdn'; destinationHost = 'fileserver.contoso.com'; ports = @('80-80'); protocol = 'tcp' }
            )
            $result = Get-GSAApplicationSegmentMatch -Segments $segments -FQDNorIP 'fileserver.contoso.com' -InputType 'FQDN' -Port 445 -Protocol 'tcp'
            $result.AddressMatched | Should -Be $true
            $result.PortMatched | Should -Be $false
        }
    }

    It 'reports no match when no segment covers the address' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $segments = @(
                [PSCustomObject]@{ destinationType = 'fqdn'; destinationHost = 'other.contoso.com'; ports = @('445-445'); protocol = 'tcp' }
            )
            $result = Get-GSAApplicationSegmentMatch -Segments $segments -FQDNorIP 'fileserver.contoso.com' -InputType 'FQDN' -Port 445 -Protocol 'tcp'
            $result.AddressMatched | Should -Be $false
        }
    }
}

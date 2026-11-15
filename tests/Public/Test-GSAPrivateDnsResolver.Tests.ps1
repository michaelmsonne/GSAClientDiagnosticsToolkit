BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAPrivateDnsResolver' {
    It 'returns nothing by default (no -PassThru)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.contoso.local'; NameServers = @('6.6.255.254') }) }
            Mock Resolve-DnsName { }
            Test-GSAPrivateDnsResolver | Should -BeNullOrEmpty
        }
    }

    It 'passes when the resolver responds successfully (Private DNS NRPT rule present)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.contoso.local'; NameServers = @('6.6.255.254') }) }
            Mock Resolve-DnsName { }
            Test-GSAPrivateDnsResolver -PassThru | Should -Be $true
        }
    }

    It 'passes when the resolver returns an NXDOMAIN-style error (still a response)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.contoso.local'; NameServers = @('6.6.255.254') }) }
            Mock Resolve-DnsName { throw 'DNS name does not exist' }
            Test-GSAPrivateDnsResolver -PassThru | Should -Be $true
        }
    }

    It 'fails when the resolver is unreachable but a Private DNS NRPT rule exists' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.contoso.local'; NameServers = @('6.6.255.254') }) }
            Mock Resolve-DnsName { throw 'A connection attempt failed because the connected party did not properly respond' }
            Test-GSAPrivateDnsResolver -PassThru | Should -Be $false
        }
    }

    It 'recognizes the GSA synthetic SLD NRPT rule (globalsecureaccess.local) as Private DNS being configured' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.appid.globalsecureaccess.local'; NameServers = @() }) }
            Mock Resolve-DnsName { }
            Test-GSAPrivateDnsResolver -PassThru | Should -Be $true
            Should -Invoke Resolve-DnsName -Times 1
        }
    }

    It 'passes as not applicable (and never probes the resolver) when no NRPT rule targets 6.6.255.254' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.contoso.com'; NameServers = @('10.0.0.1') }) }
            Mock Resolve-DnsName { throw 'Should not be called' }
            Test-GSAPrivateDnsResolver -PassThru | Should -Be $true
            Should -Invoke Resolve-DnsName -Times 0
        }
    }

    It 'passes as not applicable when there are no NRPT rules at all (Enterprise Apps only, no Quick Access)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-DnsClientNrptRule { @() }
            Mock Resolve-DnsName { throw 'Should not be called' }
            Test-GSAPrivateDnsResolver -PassThru | Should -Be $true
            Should -Invoke Resolve-DnsName -Times 0
        }
    }

    It 'falls back to probing the resolver directly when NRPT rules cannot be read' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-DnsClientNrptRule { throw 'Access denied' }
            Mock Resolve-DnsName { }
            Test-GSAPrivateDnsResolver -PassThru | Should -Be $true
            Should -Invoke Resolve-DnsName -Times 1
        }
    }

    It 'emits DEBUG log entries (including scalar Namespace/NameServers values) when -LogLevel DEBUG is set' {
        InModuleScope GSAClientDiagnosticsToolkit {
            # Namespace/NameServers as plain scalar strings (not arrays) to verify the -join logic
            # doesn't split them into individual characters.
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.contoso.local'; NameServers = '6.6.255.254' }) }
            Mock Resolve-DnsName { [PSCustomObject]@{ Type = 'A'; Name = 'connectivity.check.gsa.internal'; Section = 'Answer' } }
            Mock Write-Log {}

            Test-GSAPrivateDnsResolver -LogLevel DEBUG -PassThru | Should -Be $true

            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'DEBUG' -and $Message -like "*Namespace: '.contoso.local'*" -and $Message -like '*NameServers: 6.6.255.254*' -and $Message -match '\[MATCH\]' }
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'DEBUG' -and $Message -like '*Type: A, Name: connectivity.check.gsa.internal, Section: Answer*' }
        }
    }
}

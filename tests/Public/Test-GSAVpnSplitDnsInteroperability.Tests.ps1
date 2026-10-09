BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAVpnSplitDnsInteroperability' {
    It 'stores $true and emits no pipeline output when no active Cisco VPN adapter is detected' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-NetAdapter { @() }
            Mock Get-DnsClientNrptRule { throw 'Should not be called' }
            $script:_testResult = $null
            $result = Test-GSAVpnSplitDnsInteroperability -DnsSuffix 'mydomain.com' -PassThru
            $result | Should -BeNullOrEmpty
            $script:_testResult | Should -Be $true
            Assert-MockCalled Get-DnsClientNrptRule -Times 0 -Exactly
        }
    }

    It 'stores $true and emits no pipeline output when Cisco is active but no NRPT rule matches the suffix' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-NetAdapter { @([PSCustomObject]@{ Name = 'Cisco AnyConnect'; InterfaceDescription = 'Cisco AnyConnect Secure Mobility Client'; Status = 'Up' }) }
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.contoso.com' }) }
            Mock Resolve-DnsName { throw 'Should not be called' }
            $script:_testResult = $null
            $result = Test-GSAVpnSplitDnsInteroperability -DnsSuffix 'mydomain.com' -PassThru
            $result | Should -BeNullOrEmpty
            $script:_testResult | Should -Be $true
            Assert-MockCalled Resolve-DnsName -Times 0 -Exactly
        }
    }

    It 'stores $false and emits no pipeline output when lookup is REFUSED with Cisco active and matching NRPT' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-NetAdapter { @([PSCustomObject]@{ Name = 'Cisco Secure Client'; InterfaceDescription = 'Cisco Secure Client'; Status = 'Up' }) }
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.mydomain.com' }) }
            Mock Resolve-DnsName { throw 'Query refused' }
            $script:_testResult = $null
            $result = Test-GSAVpnSplitDnsInteroperability -DnsSuffix 'mydomain.com' -PassThru
            $result | Should -BeNullOrEmpty
            $script:_testResult | Should -Be $false
        }
    }

    It 'stores $true and emits no pipeline output when lookup is NXDOMAIN with Cisco active and matching NRPT' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-NetAdapter { @([PSCustomObject]@{ Name = 'Cisco Secure Client'; InterfaceDescription = 'Cisco Secure Client'; Status = 'Up' }) }
            Mock Get-DnsClientNrptRule { @([PSCustomObject]@{ Namespace = '.mydomain.com' }) }
            Mock Resolve-DnsName { throw 'DNS name does not exist' }
            $script:_testResult = $null
            $result = Test-GSAVpnSplitDnsInteroperability -DnsSuffix 'mydomain.com' -PassThru
            $result | Should -BeNullOrEmpty
            $script:_testResult | Should -Be $true
        }
    }
}

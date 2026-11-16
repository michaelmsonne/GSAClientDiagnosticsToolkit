BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSASecureDnsStatus' {
    It 'reports success when DoH is not enforced for either browser' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemProperty { $null }
            Test-GSASecureDnsStatus | Should -Be $true
        }
    }

    It 'still returns $true even when DoH is enabled (warning-only check)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemProperty { [PSCustomObject]@{ DnsOverHttpsMode = 'automatic' } }
            Test-GSASecureDnsStatus | Should -Be $true
        }
    }

    It 'detects Firefox DNSOverHTTPS\Enabled=1 (warning-only check)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemProperty { $null } -ParameterFilter { $Path -notmatch 'Firefox' }
            Mock Get-ItemProperty { [PSCustomObject]@{ Enabled = 1 } } -ParameterFilter { $Path -match 'Firefox' }
            Mock Write-Log {}
            Test-GSASecureDnsStatus | Should -Be $true
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'WARNING' -and $Message -like 'Mozilla Firefox:*' }
        }
    }
}

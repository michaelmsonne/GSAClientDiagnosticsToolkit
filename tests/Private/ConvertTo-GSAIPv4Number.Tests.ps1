BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-GSAIPv4Number' {
    It 'passes numeric bounds through' {
        InModuleScope GSAClientDiagnosticsToolkit {
            ConvertTo-GSAIPv4Number -Value 3232235777 | Should -Be 3232235777
        }
    }

    It 'converts the {f=4; v=<ip>} object format' {
        InModuleScope GSAClientDiagnosticsToolkit {
            ConvertTo-GSAIPv4Number -Value ([PSCustomObject]@{ f = 4; v = '192.168.1.1' }) | Should -Be 3232235777
        }
    }

    It 'converts a dotted string' {
        InModuleScope GSAClientDiagnosticsToolkit {
            ConvertTo-GSAIPv4Number -Value '10.0.0.0' | Should -Be 167772160
        }
    }

    It 'returns $null for IPv6 and unparseable values' {
        InModuleScope GSAClientDiagnosticsToolkit {
            ConvertTo-GSAIPv4Number -Value ([PSCustomObject]@{ f = 6; v = 'fd00::1' }) | Should -BeNullOrEmpty
            ConvertTo-GSAIPv4Number -Value ([PSCustomObject]@{ f = 4; v = 'not-an-ip' }) | Should -BeNullOrEmpty
            ConvertTo-GSAIPv4Number -Value $null | Should -BeNullOrEmpty
            ConvertTo-GSAIPv4Number -Value ([PSCustomObject]@{ x = 1 }) | Should -BeNullOrEmpty
        }
    }
}

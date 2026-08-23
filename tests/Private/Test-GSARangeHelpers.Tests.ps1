BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAIPInRange' {
    It 'returns $true when the IP falls within the range' {
        InModuleScope GSAClientDiagnosticsToolkit {
            # 10.0.0.0 = 167772160, 10.0.0.255 = 167772415 (decimal, big-endian)
            Test-GSAIPInRange -Start 167772160 -End 167772415 -IPAddress '10.0.0.42' | Should -Be $true
        }
    }

    It 'returns $false when the IP falls outside the range' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Test-GSAIPInRange -Start 167772160 -End 167772415 -IPAddress '10.0.1.1' | Should -Be $false
        }
    }
}

Describe 'Test-GSAPortInRange' {
    It 'returns $true when the port falls within one of the ranges' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $ports = @(
                [PSCustomObject]@{ start = 80; end = 80 }
                [PSCustomObject]@{ start = 400; end = 500 }
            )
            Test-GSAPortInRange -Ports $ports -Port 445 | Should -Be $true
        }
    }

    It 'returns $false when the port does not fall within any range' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $ports = @([PSCustomObject]@{ start = 80; end = 80 })
            Test-GSAPortInRange -Ports $ports -Port 445 | Should -Be $false
        }
    }
}

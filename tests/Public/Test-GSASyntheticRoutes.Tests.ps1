BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSASyntheticRoutes' {
    It 'passes when GSA synthetic routes (6.6.x.x) are present' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-NetRoute { @([PSCustomObject]@{ DestinationPrefix = '6.6.0.1/32'; NextHop = '0.0.0.0'; InterfaceAlias = 'GSA Tunnel' }) }
            Test-GSASyntheticRoutes | Should -Be $true
        }
    }

    It 'reports a warning when no synthetic routes are found' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-NetRoute { @([PSCustomObject]@{ DestinationPrefix = '0.0.0.0/0'; NextHop = '10.0.0.1'; InterfaceAlias = 'Ethernet' }) }
            $result = Test-GSASyntheticRoutes
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 1
        }
    }

    It 'fails when the routing table cannot be queried' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-NetRoute { throw 'Access denied' }
            Test-GSASyntheticRoutes | Should -Be $false
        }
    }
}

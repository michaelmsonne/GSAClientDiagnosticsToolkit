BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAClientProfileConnectivity' {
    It 'fails when the registry configuration cannot be loaded' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { $null }
            Test-GSAClientProfileConnectivity -ProfileType private -PassThru | Should -Be $false
        }
    }

    It 'fails when the requested channel is not present' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { '{"policy":{"channels":[{"name":"m365"}]}}' }
            Test-GSAClientProfileConnectivity -ProfileType private -PassThru | Should -Be $false
        }
    }

    It 'fails when neither edge is reachable' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"channels":[{"name":"private","diagnosticUri":"https://diag.example.com","edgesSettings":{"primaryEdges":[{"edgeAddress":"edge1.example.com","edgePort":443}],"secondaryEdges":[{"edgeAddress":"edge2.example.com","edgePort":443}]}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Mock Test-NetConnection { $false }
            Test-GSAClientProfileConnectivity -ProfileType private -PassThru | Should -Be $false
        }
    }

    It 'passes when the primary edge and diagnostic endpoint are reachable' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"channels":[{"name":"private","diagnosticUri":"https://diag.example.com","edgesSettings":{"primaryEdges":[{"edgeAddress":"edge1.example.com","edgePort":443}],"secondaryEdges":[{"edgeAddress":"edge2.example.com","edgePort":443}]}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Mock Test-NetConnection { $true }
            Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = 'pong' } }
            Test-GSAClientProfileConnectivity -ProfileType private -PassThru | Should -Be $true
        }
    }

    It 'fails when the diagnostic endpoint does not respond with pong' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"channels":[{"name":"private","diagnosticUri":"https://diag.example.com","edgesSettings":{"primaryEdges":[{"edgeAddress":"edge1.example.com","edgePort":443}],"secondaryEdges":[{"edgeAddress":"edge2.example.com","edgePort":443}]}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Mock Test-NetConnection { $true }
            Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = 'unexpected' } }
            Test-GSAClientProfileConnectivity -ProfileType private -PassThru | Should -Be $false
        }
    }

    It 'tests all three profile types when -ProfileType is not specified' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"channels":[' +
                '{"name":"m365","diagnosticUri":"https://diag.example.com","edgesSettings":{"primaryEdges":[{"edgeAddress":"edge1.example.com","edgePort":443}],"secondaryEdges":[{"edgeAddress":"edge2.example.com","edgePort":443}]}},' +
                '{"name":"private","diagnosticUri":"https://diag.example.com","edgesSettings":{"primaryEdges":[{"edgeAddress":"edge1.example.com","edgePort":443}],"secondaryEdges":[{"edgeAddress":"edge2.example.com","edgePort":443}]}},' +
                '{"name":"internet","diagnosticUri":"https://diag.example.com","edgesSettings":{"primaryEdges":[{"edgeAddress":"edge1.example.com","edgePort":443}],"secondaryEdges":[{"edgeAddress":"edge2.example.com","edgePort":443}]}}' +
                ']}}'
            Mock Get-ItemPropertyValue { $json }
            Mock Test-NetConnection { $true }
            Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = 'pong' } }

            Test-GSAClientProfileConnectivity -PassThru | Should -Be $true

            Should -Invoke Invoke-WebRequest -Times 3 -Exactly
        }
    }

    It 'reports overall failure when only one of several tested profiles fails' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"channels":[{"name":"m365"},{"name":"private","diagnosticUri":"https://diag.example.com","edgesSettings":{"primaryEdges":[{"edgeAddress":"edge1.example.com","edgePort":443}],"secondaryEdges":[{"edgeAddress":"edge2.example.com","edgePort":443}]}}]}}'
            Mock Get-ItemPropertyValue { $json }
            Mock Test-NetConnection { $true }
            Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = 'pong' } }

            # m365 channel is missing edgesSettings/diagnosticUri -> present but should fail; private should pass
            Test-GSAClientProfileConnectivity -ProfileType m365, private -PassThru | Should -Be $false
        }
    }
}

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Get-GSAEndpoints' {
    It 'returns edge addresses and diagnostic URIs, plus the APS endpoint' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = '{"policy":{"channels":[{"name":"M365","diagnosticUri":"https://diag.example.com/m365","edgesSettings":{"primaryEdges":[{"edgeAddress":"edge1.example.com"}]}}]}}'
            Mock Get-ItemPropertyValue { $json }

            $result = Get-GSAEndpoints

            $result.MainEndpoints | Should -Contain 'edge1.example.com'
            $result.MainEndpoints | Should -Contain 'aps.globalsecureaccess.microsoft.com'
            $result.DiagnosticUris | Should -Contain 'https://diag.example.com/m365'
        }
    }

    It 'returns $null when the registry configuration cannot be loaded' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { $null }
            Get-GSAEndpoints | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when no channels/edge addresses are found' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { '{"policy":{"channels":[]}}' }
            Get-GSAEndpoints | Should -BeNullOrEmpty
        }
    }
}

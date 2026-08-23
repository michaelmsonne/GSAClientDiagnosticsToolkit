BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Get-GSAMainEndpoints' {
    It 'extracts primary and secondary edge addresses per channel' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = [PSCustomObject]@{
                policy = [PSCustomObject]@{
                    channels = @(
                        [PSCustomObject]@{
                            name          = 'M365'
                            diagnosticUri = 'https://diag.example.com/m365'
                            edgesSettings = [PSCustomObject]@{
                                primaryEdges   = @([PSCustomObject]@{ edgeAddress = 'edge1.example.com' })
                                secondaryEdges = @([PSCustomObject]@{ edgeAddress = 'edge2.example.com' })
                            }
                        }
                    )
                }
            }

            $result = @(Get-GSAMainEndpoints -jsonContent $json)

            $result.Count | Should -Be 1
            $result[0].ChannelName | Should -Be 'M365'
            $result[0].DiagnosticUri | Should -Be 'https://diag.example.com/m365'
            $result[0].EdgeAddresses | Should -Contain 'edge1.example.com'
            $result[0].EdgeAddresses | Should -Contain 'edge2.example.com'
        }
    }

    It 'returns an empty array when no channels are present' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = [PSCustomObject]@{ policy = [PSCustomObject]@{ channels = @() } }
            $result = Get-GSAMainEndpoints -jsonContent $json
            $result.Count | Should -Be 0
        }
    }

    It 'handles a channel with no edges settings' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $json = [PSCustomObject]@{
                policy = [PSCustomObject]@{
                    channels = @([PSCustomObject]@{ name = 'Internet'; diagnosticUri = $null; edgesSettings = $null })
                }
            }
            $result = @(Get-GSAMainEndpoints -jsonContent $json)
            $result.Count | Should -Be 1
            $result[0].EdgeAddresses.Count | Should -Be 0
        }
    }
}

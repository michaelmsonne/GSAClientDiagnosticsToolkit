BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Get-GSAPrivateAccessApplicationDisplayNames' {
    It 'builds an appId to displayName map from the Graph response' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{ appId = 'app-1'; displayName = 'FileServer App' }
                        [PSCustomObject]@{ appId = 'app-2'; displayName = 'RDP App' }
                    )
                }
            }
            $map = Get-GSAPrivateAccessApplicationDisplayNames
            $map['app-1'] | Should -Be 'FileServer App'
            $map['app-2'] | Should -Be 'RDP App'
        }
    }

    It 'returns an empty map when Microsoft Graph fails' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { throw 'Graph unavailable' }
            $map = Get-GSAPrivateAccessApplicationDisplayNames
            $map.Count | Should -Be 0
        }
    }
}

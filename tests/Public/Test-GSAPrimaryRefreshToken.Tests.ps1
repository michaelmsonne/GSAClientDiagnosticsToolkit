BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAPrimaryRefreshToken' {
    It 'passes when a Primary Refresh Token is present' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock dsregcmd { @('AzureAdPrt : YES', 'AzureAdPrtUpdateTime : 2026-01-01') }
            Test-GSAPrimaryRefreshToken | Should -Be $true
        }
    }

    It 'fails when no Primary Refresh Token is present' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock dsregcmd { @('AzureAdPrt : NO') }
            Test-GSAPrimaryRefreshToken | Should -Be $false
        }
    }

    It 'fails when dsregcmd throws' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock dsregcmd { throw 'command not found' }
            Test-GSAPrimaryRefreshToken | Should -Be $false
        }
    }
}

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAPrimaryRefreshToken' {
    It 'passes when a Primary Refresh Token is present' {
        InModuleScope GSAClientConnectivityChecker {
            Mock dsregcmd { @('AzureAdPrt : YES', 'AzureAdPrtUpdateTime : 2026-01-01') }
            Test-GSAPrimaryRefreshToken | Should -Be $true
        }
    }

    It 'fails when no Primary Refresh Token is present' {
        InModuleScope GSAClientConnectivityChecker {
            Mock dsregcmd { @('AzureAdPrt : NO') }
            Test-GSAPrimaryRefreshToken | Should -Be $false
        }
    }

    It 'fails when dsregcmd throws' {
        InModuleScope GSAClientConnectivityChecker {
            Mock dsregcmd { throw 'command not found' }
            Test-GSAPrimaryRefreshToken | Should -Be $false
        }
    }
}

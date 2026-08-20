BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Get-GSACurrentUserUPN' {
    It 'returns the trimmed output of whoami /upn on success' {
        InModuleScope GSAClientConnectivityChecker {
            Mock whoami { 'user@contoso.com' }
            Get-GSACurrentUserUPN | Should -Be 'user@contoso.com'
        }
    }
}

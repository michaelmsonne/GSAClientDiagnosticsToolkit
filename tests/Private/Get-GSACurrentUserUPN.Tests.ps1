BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Get-GSACurrentUserUPN' {
    It 'returns the trimmed output of whoami /upn on success' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock whoami { 'user@contoso.com' }
            Get-GSACurrentUserUPN | Should -Be 'user@contoso.com'
        }
    }
}

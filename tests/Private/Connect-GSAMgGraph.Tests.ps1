BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Connect-GSAMgGraph' {
    It 'throws when Microsoft.Graph.Authentication is not installed' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable }
            { Connect-GSAMgGraph -Scopes @('User.Read.All') } | Should -Throw
        }
    }

    It 'connects when there is no active Graph session' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-Module { [PSCustomObject]@{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter { $ListAvailable }
            Mock Import-Module {}
            Mock Get-MgContext { $null }
            Mock Connect-MgGraph {}
            Connect-GSAMgGraph -Scopes @('User.Read.All')
            Should -Invoke Connect-MgGraph -Times 1 -Exactly
        }
    }

    It 'connects when the active session is missing a required scope' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-Module { [PSCustomObject]@{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter { $ListAvailable }
            Mock Import-Module {}
            Mock Get-MgContext { [PSCustomObject]@{ Scopes = @('User.Read') } }
            Mock Connect-MgGraph {}
            Connect-GSAMgGraph -Scopes @('User.Read.All')
            Should -Invoke Connect-MgGraph -Times 1 -Exactly
        }
    }

    It 'does not reconnect when an active session already has the required scopes' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-Module { [PSCustomObject]@{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter { $ListAvailable }
            Mock Import-Module {}
            Mock Get-MgContext { [PSCustomObject]@{ Scopes = @('User.Read.All', 'Application.Read.All') } }
            Mock Connect-MgGraph {}
            Connect-GSAMgGraph -Scopes @('User.Read.All')
            Should -Invoke Connect-MgGraph -Times 0 -Exactly
        }
    }
}

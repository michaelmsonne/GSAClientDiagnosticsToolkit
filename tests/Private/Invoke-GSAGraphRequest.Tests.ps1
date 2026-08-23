BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-GSAGraphRequest' {
    It 'returns the response from Invoke-RestMethod on success' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-RestMethod { [PSCustomObject]@{ value = 'ok' } }
            $result = Invoke-GSAGraphRequest -AccessToken 'token' -Uri 'https://graph.microsoft.com/v1.0/me'
            $result.value | Should -Be 'ok'
        }
    }

    It 'sends a JSON body for non-GET requests' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-RestMethod { [PSCustomObject]@{ value = @() } }
            Invoke-GSAGraphRequest -AccessToken 'token' -Uri 'https://graph.microsoft.com/beta/x' -Method 'POST' -Body @{ groupIds = @('a') }
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Body -match 'groupIds' }
        }
    }

    It 'rethrows non-throttling errors' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-RestMethod { throw 'boom' }
            { Invoke-GSAGraphRequest -AccessToken 'token' -Uri 'https://graph.microsoft.com/v1.0/me' } | Should -Throw
        }
    }

    It 'triggers an interactive Graph sign-in and uses Invoke-MgGraphRequest when no -AccessToken is supplied' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Connect-GSAMgGraph {}
            Mock Invoke-MgGraphRequest { [PSCustomObject]@{ value = 'ok' } }
            $result = Invoke-GSAGraphRequest -Uri 'https://graph.microsoft.com/v1.0/me'
            $result.value | Should -Be 'ok'
            Should -Invoke Connect-GSAMgGraph -Times 1 -Exactly
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    It 'does not call Connect-GSAMgGraph when an -AccessToken is supplied' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Connect-GSAMgGraph {}
            Mock Invoke-RestMethod { [PSCustomObject]@{ value = 'ok' } }
            Invoke-GSAGraphRequest -AccessToken 'token' -Uri 'https://graph.microsoft.com/v1.0/me' | Out-Null
            Should -Invoke Connect-GSAMgGraph -Times 0 -Exactly
        }
    }
}

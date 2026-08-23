BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAPrivateAccessApplication' {
    It 'fails when no application is found' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ value = @() } }
            Test-GSAPrivateAccessApplication -AccessToken 'token' -AppId 'app-1' -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'fails when GSA client access is not enabled on the application' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ value = @([PSCustomObject]@{ displayName = 'App'; appId = 'app-1'; id = 'obj-1'; tags = @() }) } }
            Test-GSAPrivateAccessApplication -AccessToken 'token' -AppId 'app-1' -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'fails when the application segment check fails' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ value = @([PSCustomObject]@{ displayName = 'App'; appId = 'app-1'; id = 'obj-1'; tags = @('IsAccessibleViaZTNAClient') }) } }
            Mock Test-GSAPrivateAccessApplicationSegment { $false }
            Test-GSAPrivateAccessApplication -AccessToken 'token' -AppId 'app-1' -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'passes when GSA-enabled, segment matches, and the tunnel test succeeds' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ value = @([PSCustomObject]@{ displayName = 'App'; appId = 'app-1'; id = 'obj-1'; tags = @('IsAccessibleViaZTNAClient') }) } }
            Mock Test-GSAPrivateAccessApplicationSegment { $true }
            Mock Test-GSAPrivateAccessTunnel { $true }
            Test-GSAPrivateAccessApplication -AccessToken 'token' -AppId 'app-1' -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $true
        }
    }

    It 'fails when the tunnel test fails even if the segment check passes' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ value = @([PSCustomObject]@{ displayName = 'App'; appId = 'app-1'; id = 'obj-1'; tags = @('IsAccessibleViaZTNAClient') }) } }
            Mock Test-GSAPrivateAccessApplicationSegment { $true }
            Mock Test-GSAPrivateAccessTunnel { $false }
            Test-GSAPrivateAccessApplication -AccessToken 'token' -AppId 'app-1' -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }
}

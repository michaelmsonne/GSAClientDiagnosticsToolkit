BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAPrivateAccessApplicationSegment' {
    It 'fails when the target is not a valid FQDN or IP' {
        InModuleScope GSAClientConnectivityChecker {
            Test-GSAPrivateAccessApplicationSegment -AccessToken 'token' -AppId 'app-1' -FQDNorIP 'not a host' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'fails when the application is disabled' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-GSACurrentUserUPN { 'user@contoso.com' }
            Mock Invoke-GSAGraphRequest { [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'sp-1'; accountEnabled = $false }) } }
            Test-GSAPrivateAccessApplicationSegment -AccessToken 'token' -AppId 'app-1' -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }

    It 'passes when enabled, assignment not required, and segment matches' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-GSACurrentUserUPN { 'user@contoso.com' }
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'servicePrincipals') { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'sp-1'; accountEnabled = $true; appRoleAssignmentRequired = $false; appRoleAssignedTo = @() }) } }
                if ($Uri -match 'applicationSegments') { return [PSCustomObject]@{ value = @([PSCustomObject]@{ destinationType = 'fqdn'; destinationHost = 'fileserver.contoso.com'; ports = @('445-445'); protocol = 'tcp' }) } }
            }
            Test-GSAPrivateAccessApplicationSegment -AccessToken 'token' -AppId 'app-1' -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $true
        }
    }

    It 'fails when no application segment covers the address' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-GSACurrentUserUPN { 'user@contoso.com' }
            Mock Invoke-GSAGraphRequest {
                param($Uri)
                if ($Uri -match 'servicePrincipals') { return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'sp-1'; accountEnabled = $true; appRoleAssignmentRequired = $false; appRoleAssignedTo = @() }) } }
                if ($Uri -match 'applicationSegments') { return [PSCustomObject]@{ value = @([PSCustomObject]@{ destinationType = 'fqdn'; destinationHost = 'other.contoso.com'; ports = @('445-445'); protocol = 'tcp' }) } }
            }
            Test-GSAPrivateAccessApplicationSegment -AccessToken 'token' -AppId 'app-1' -FQDNorIP 'fileserver.contoso.com' -Port 445 -Protocol TCP -PassThru | Should -Be $false
        }
    }
}

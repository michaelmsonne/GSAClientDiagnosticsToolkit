BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAServiceStatus' {
    It 'fails fast when the GSA Client is not installed' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $false }
            Test-GSAServiceStatus
            $script:_testResult.Passed | Should -Be $false
        }
    }

    It 'passes when all required services and the forwarding profile service are running' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $true }
            Mock Get-Service {
                param($Name)
                [PSCustomObject]@{ Name = $Name; Status = 'Running'; StartType = 'Automatic' }
            }
            Test-GSAServiceStatus
            $script:_testResult.Passed | Should -Be $true
        }
    }

    It 'fails when a required service is not running' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $true }
            Mock Get-Service {
                param($Name)
                $status = if ($Name -eq 'GlobalSecureAccessEngineService') { 'Stopped' } else { 'Running' }
                [PSCustomObject]@{ Name = $Name; Status = $status; StartType = 'Automatic' }
            }
            Test-GSAServiceStatus
            $script:_testResult.Passed | Should -Be $false
        }
    }

    It 'fails when neither forwarding profile service is registered' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Test-Path { $true }
            Mock Get-Service {
                param($Name)
                if ($Name -in @('GlobalSecureAccessPolicyRetrieverService', 'GlobalSecureAccessForwardingProfileService')) {
                    return $null
                }
                [PSCustomObject]@{ Name = $Name; Status = 'Running'; StartType = 'Automatic' }
            }
            Test-GSAServiceStatus
            $script:_testResult.Passed | Should -Be $false
        }
    }
}

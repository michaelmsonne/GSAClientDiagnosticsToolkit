BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Test-ProxyDetection' {
    It 'reports no proxy when nothing is detected' {
        InModuleScope GSAClientConnectivityChecker {
            Mock netsh { 'Direct access (no proxy server).' }
            Mock Test-grpcProxy { $false }
            Mock Test-SystemWebProxy { $null }
            Mock Invoke-WebRequest { [PSCustomObject]@{ Headers = @{}; StatusCode = 200 } }

            $result = Test-ProxyDetection

            $result.ProxyFound | Should -Be $false
            $result.SystemProxyConfigured | Should -Be $false
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 0
        }
    }

    It 'detects a system proxy from netsh output' {
        InModuleScope GSAClientConnectivityChecker {
            Mock netsh { 'Proxy Server :  proxy.example.com:8080' }
            Mock Test-grpcProxy { $false }
            Mock Test-SystemWebProxy { $null }
            Mock Invoke-WebRequest { [PSCustomObject]@{ Headers = @{}; StatusCode = 200 } }

            $result = Test-ProxyDetection

            $result.SystemProxyConfigured | Should -Be $true
            $result.ProxyFound | Should -Be $true
            $result.Warnings | Should -BeGreaterThan 0
        }
    }

    It 'detects a transparent proxy via response headers' {
        InModuleScope GSAClientConnectivityChecker {
            Mock netsh { 'Direct access (no proxy server).' }
            Mock Test-grpcProxy { $false }
            Mock Test-SystemWebProxy { $null }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ Headers = @{ Via = '1.1 proxy.example.com' }; StatusCode = 200 }
            }

            $result = Test-ProxyDetection

            $result.TransparentProxyDetected | Should -Be $true
            $result.ProxyFound | Should -Be $true
        }
    }

    It 'detects an authenticating proxy via an HTTP 407 response' {
        InModuleScope GSAClientConnectivityChecker {
            Mock netsh { 'Direct access (no proxy server).' }
            Mock Test-grpcProxy { $false }
            Mock Test-SystemWebProxy { $null }
            Mock Invoke-WebRequest {
                param($Uri)
                if ($Uri -eq 'https://www.microsoft.com') {
                    $exception = New-Object System.Exception 'Proxy Authentication Required'
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([PSCustomObject]@{ StatusCode = 407 }) -Force
                    throw $exception
                }
                [PSCustomObject]@{ Headers = @{}; StatusCode = 200 }
            }

            $result = Test-ProxyDetection

            $result.AuthenticatingProxyDetected | Should -Be $true
            $result.ProxyFound | Should -Be $true
        }
    }
}

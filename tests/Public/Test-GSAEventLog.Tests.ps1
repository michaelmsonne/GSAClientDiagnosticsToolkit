BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAEventLog' {
    It 'reports a warning when the GSA event log is not registered' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-WinEvent { $null } -ParameterFilter { $ListLog }
            $result = Test-GSAEventLog
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 1
        }
    }

    It 'passes when no Critical/Error/Warning events are found' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-WinEvent { [PSCustomObject]@{ LogName = $ListLog } } -ParameterFilter { $ListLog }
            Mock Get-WinEvent { @() } -ParameterFilter { $LogName }
            Test-GSAEventLog | Should -Be $true
        }
    }

    It 'reports warnings when Critical/Error events are found in the last hour' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Get-WinEvent { [PSCustomObject]@{ LogName = $ListLog } } -ParameterFilter { $ListLog }
            Mock Get-WinEvent {
                # Two events are used deliberately: a single-item array unwraps to a scalar
                # object in PowerShell, which would mask a $errors.Count bug in the caller.
                @(
                    [PSCustomObject]@{ Id = 141; Level = 2; TimeCreated = (Get-Date); Message = 'Edge connection failed' }
                    [PSCustomObject]@{ Id = 631; Level = 2; TimeCreated = (Get-Date); Message = 'Disconnected from ALL channels' }
                )
            } -ParameterFilter { $LogName }

            $result = Test-GSAEventLog

            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 2
        }
    }
}

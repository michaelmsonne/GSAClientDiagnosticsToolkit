BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientConnectivityChecker.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientConnectivityChecker -Force -ErrorAction SilentlyContinue
}

Describe 'Write-Log' {
    AfterEach {
        InModuleScope GSAClientConnectivityChecker {
            if ($script:LogFilePath -and (Test-Path $script:LogFilePath)) {
                Remove-Item $script:LogFilePath -Force -ErrorAction SilentlyContinue
            }
            $script:LogFilePath = $null
            $script:LogLevel = 'INFO'
        }
    }

    It 'writes to the console when the message level is at or below the current LogLevel' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Write-Host {}
            $script:LogLevel = 'INFO'
            Write-Log -Message 'info message' -Level 'INFO'
            Should -Invoke Write-Host -Times 1 -Exactly
        }
    }

    It 'suppresses console output for levels more verbose than the current LogLevel' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Write-Host {}
            $script:LogLevel = 'ERROR'
            Write-Log -Message 'debug message' -Level 'DEBUG'
            Should -Invoke Write-Host -Times 0 -Exactly
        }
    }

    It 'always writes SUCCESS messages to the console regardless of LogLevel' {
        InModuleScope GSAClientConnectivityChecker {
            Mock Write-Host {}
            $script:LogLevel = 'ERROR'
            Write-Log -Message 'success message' -Level 'SUCCESS'
            Should -Invoke Write-Host -Times 1 -Exactly
        }
    }

    It 'writes every message to the log file once a log file path is set' {
        InModuleScope GSAClientConnectivityChecker {
            $script:LogFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString() + '.log')
            Write-Log -Message 'file message' -Level 'DEBUG'
            Get-Content $script:LogFilePath -Raw | Should -Match 'file message'
        }
    }

    It 'does not throw when no log file path is configured' {
        InModuleScope GSAClientConnectivityChecker {
            $script:LogFilePath = $null
            { Write-Log -Message 'no file yet' -Level 'INFO' } | Should -Not -Throw
        }
    }
}

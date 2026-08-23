BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Write-Log' {
    AfterEach {
        InModuleScope GSAClientDiagnosticsToolkit {
            if ($script:LogFilePath -and (Test-Path $script:LogFilePath)) {
                Remove-Item $script:LogFilePath -Force -ErrorAction SilentlyContinue
            }
            $script:LogFilePath = $null
            $script:LogLevel = 'INFO'
        }
    }

    It 'writes to the console when the message level is at or below the current LogLevel' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Write-Host {}
            $script:LogLevel = 'INFO'
            Write-Log -Message 'info message' -Level 'INFO'
            Should -Invoke Write-Host -Times 1 -Exactly
        }
    }

    It 'suppresses console output for levels more verbose than the current LogLevel' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Write-Host {}
            $script:LogLevel = 'ERROR'
            Write-Log -Message 'debug message' -Level 'DEBUG'
            Should -Invoke Write-Host -Times 0 -Exactly
        }
    }

    It 'always writes SUCCESS messages to the console regardless of LogLevel' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Write-Host {}
            $script:LogLevel = 'ERROR'
            Write-Log -Message 'success message' -Level 'SUCCESS'
            Should -Invoke Write-Host -Times 1 -Exactly
        }
    }

    It 'writes every message to the log file once a log file path is set' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $script:LogFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString() + '.log')
            Write-Log -Message 'file message' -Level 'DEBUG'
            Get-Content $script:LogFilePath -Raw | Should -Match 'file message'
        }
    }

    It 'does not throw when no log file path is configured' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $script:LogFilePath = $null
            { Write-Log -Message 'no file yet' -Level 'INFO' } | Should -Not -Throw
        }
    }
}

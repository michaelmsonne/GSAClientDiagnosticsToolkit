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

    It 'writes messages at or below the current LogLevel to the log file' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Write-Host {}
            $script:LogFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString() + '.log')
            $script:LogLevel = 'DEBUG'
            Write-Log -Message 'file message' -Level 'DEBUG'
            Get-Content $script:LogFilePath -Raw | Should -Match 'file message'
        }
    }

    It 'does not write levels more verbose than the current LogLevel to the log file, but still writes SUCCESS' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Write-Host {}
            $script:LogFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString() + '.log')
            $script:LogLevel = 'INFO'
            Write-Log -Message 'hidden debug message' -Level 'DEBUG'
            Write-Log -Message 'visible success message' -Level 'SUCCESS'
            $content = Get-Content $script:LogFilePath -Raw
            $content | Should -Not -Match 'hidden debug message'
            $content | Should -Match 'visible success message'
        }
    }

    It 'does not throw when no log file path is configured' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $script:LogFilePath = $null
            { Write-Log -Message 'no file yet' -Level 'INFO' } | Should -Not -Throw
        }
    }
}

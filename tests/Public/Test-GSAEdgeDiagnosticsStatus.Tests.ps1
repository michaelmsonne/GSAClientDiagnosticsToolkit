BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAEdgeDiagnosticsStatus' {
    It 'returns nothing by default (no -PassThru)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $fresh = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            Mock Get-ItemPropertyValue { "$fresh|User|Entra:0|M365:0|Private:0|Internet:0" }
            Test-GSAEdgeDiagnosticsStatus | Should -BeNullOrEmpty
        }
    }

    It 'passes when all channels report healthy (code 0)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $fresh = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            Mock Get-ItemPropertyValue { "$fresh|User|Entra:0|M365:0|Private:0|Internet:0" }
            Test-GSAEdgeDiagnosticsStatus -PassThru | Should -Be $true
        }
    }

    It 'fails when any channel reports unhealthy (non-zero code)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $fresh = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            Mock Get-ItemPropertyValue { "$fresh|User|Entra:0|M365:0|Private:1|Internet:0" }
            Test-GSAEdgeDiagnosticsStatus -PassThru | Should -Be $false
        }
    }

    It 'fails when the EdsResults registry value is missing' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { $null }
            Test-GSAEdgeDiagnosticsStatus -PassThru | Should -Be $false
        }
    }

    It 'fails when the EdsResults value is not in the expected pipe-delimited format' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { 'garbage-value' }
            Test-GSAEdgeDiagnosticsStatus -PassThru | Should -Be $false
        }
    }

    It 'still passes (but warns) when the timestamp is stale but all channels are healthy' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $stale = (Get-Date).ToUniversalTime().AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            Mock Get-ItemPropertyValue { "$stale|User|Entra:0|M365:0|Private:0|Internet:0" }
            Mock Write-Log {}
            Test-GSAEdgeDiagnosticsStatus -StaleAfterMinutes 15 -PassThru | Should -Be $true
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'WARNING' -and $Message -like '*stalled*' }
        }
    }
}

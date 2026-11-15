BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAHyperVExternalSwitch' {
    AfterEach {
        InModuleScope GSAClientDiagnosticsToolkit {
            $script:LogLevel = 'INFO'
        }
    }

    It 'logs query results and switch properties only at DEBUG level' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Write-Log {}
            Mock Get-VMSwitch {
                @([PSCustomObject]@{
                    Name = 'ExternalSwitch'
                    Id = 'switch-id'
                    SwitchType = 'External'
                    NetAdapterInterfaceDescription = 'Ethernet Adapter'
                    AllowManagementOS = $true
                })
            }

            Test-GSAHyperVExternalSwitch -LogLevel INFO | Should -BeNullOrEmpty
            Should -Invoke Write-Log -Times 0 -Exactly -ParameterFilter { $Level -eq 'DEBUG' }

            Test-GSAHyperVExternalSwitch -LogLevel DEBUG | Should -BeNullOrEmpty
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'DEBUG' -and $Message -like '*Get-VMSwitch -SwitchType External*'
            }
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'DEBUG' -and $Message -like '*returned 1 external*'
            }
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'DEBUG' -and $Message -like "*Id='switch-id'*AllowManagementOS='True'*"
            }
        }
    }

    It 'logs query errors at an inherited DEBUG level without changing the result' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $script:LogLevel = 'DEBUG'
            Mock Write-Log {}
            Mock Get-VMSwitch { throw 'Hyper-V query unavailable' }

            Test-GSAHyperVExternalSwitch -PassThru | Should -Be $true
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'DEBUG' -and $Message -like "*Hyper-V query failed:*Message='Hyper-V query unavailable'*"
            }
        }
    }

    It 'returns nothing by default (no -PassThru)' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { @() }
            Test-GSAHyperVExternalSwitch | Should -BeNullOrEmpty
        }
    }

    It 'passes when no Hyper-V external virtual switch is found' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { @() }
            Test-GSAHyperVExternalSwitch -PassThru | Should -Be $true
        }
    }

    It 'passes when Hyper-V is not installed/available on this host' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { throw 'The term ''Get-VMSwitch'' is not recognized...' }
            Test-GSAHyperVExternalSwitch -PassThru | Should -Be $true
        }
    }

    It 'reports a warning (still passes) when a Hyper-V external virtual switch is found' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { @([PSCustomObject]@{ Name = 'ExternalSwitch'; SwitchType = 'External'; NetAdapterInterfaceDescription = 'Ethernet Adapter' }) }
            $result = Test-GSAHyperVExternalSwitch -PassThru
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 1
        }
    }

    It 'queries Get-VMSwitch with -SwitchType External' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-VMSwitch { @() }
            Test-GSAHyperVExternalSwitch -PassThru | Out-Null
            Should -Invoke Get-VMSwitch -ParameterFilter { $SwitchType -eq 'External' }
        }
    }
}

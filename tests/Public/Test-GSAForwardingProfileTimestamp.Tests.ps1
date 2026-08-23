BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Test-GSAForwardingProfileTimestamp' {
    It 'reports a warning when the timestamp value is missing' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { $null }
            $result = Test-GSAForwardingProfileTimestamp
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 1
        }
    }

    It 'passes when the profile was retrieved recently' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $recent = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o')
            Mock Get-ItemPropertyValue { $recent }
            Test-GSAForwardingProfileTimestamp | Should -Be $true
        }
    }

    It 'reports a warning when the profile timestamp is stale' {
        InModuleScope GSAClientDiagnosticsToolkit {
            $stale = (Get-Date).ToUniversalTime().AddHours(-5).ToString('o')
            Mock Get-ItemPropertyValue { $stale }
            $result = Test-GSAForwardingProfileTimestamp
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 1
        }
    }

    It 'reports a warning when the timestamp value cannot be parsed as a date' {
        InModuleScope GSAClientDiagnosticsToolkit {
            Mock Get-ItemPropertyValue { 'not-a-date' }
            $result = Test-GSAForwardingProfileTimestamp
            $result.Passed | Should -Be $true
            $result.Warnings | Should -Be 1
        }
    }
}

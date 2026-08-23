BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Save-EdgeAddresses' {
    It 'writes the FQDN list to the target file' {
        $targetFile = Join-Path $TestDrive 'edges.txt'
        Save-EdgeAddresses -fqdnList @('edge1.example.com', 'edge2.example.com') -filePath $targetFile
        Get-Content $targetFile | Should -Be @('edge1.example.com', 'edge2.example.com')
    }

    It 'creates the destination directory if it does not exist' {
        $targetFile = Join-Path $TestDrive 'nested\folder\edges.txt'
        Save-EdgeAddresses -fqdnList @('edge1.example.com') -filePath $targetFile
        Test-Path $targetFile | Should -Be $true
    }

    It 'does not write a file when given an empty FQDN list' {
        $targetFile = Join-Path $TestDrive 'empty.txt'
        { Save-EdgeAddresses -fqdnList @() -filePath $targetFile } | Should -Not -Throw
        Test-Path $targetFile | Should -Be $false
    }

    It 'does not throw when no file path is specified' {
        { Save-EdgeAddresses -fqdnList @('edge1.example.com') -filePath $null } | Should -Not -Throw
    }
}

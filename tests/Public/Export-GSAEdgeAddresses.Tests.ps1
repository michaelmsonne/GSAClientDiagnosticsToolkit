BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module GSAClientDiagnosticsToolkit -Force -ErrorAction SilentlyContinue
}

Describe 'Export-GSAEdgeAddresses' {
    It 'writes the FQDN list to the target file' {
        $targetFile = Join-Path $TestDrive 'edges.txt'
        Export-GSAEdgeAddresses -fqdnList @('edge1.example.com', 'edge2.example.com') -filePath $targetFile
        Get-Content $targetFile | Should -Be @('edge1.example.com', 'edge2.example.com')
    }

    It 'creates the destination directory if it does not exist' {
        $targetFile = Join-Path $TestDrive 'nested\folder\edges.txt'
        Export-GSAEdgeAddresses -fqdnList @('edge1.example.com') -filePath $targetFile
        Test-Path $targetFile | Should -Be $true
    }

    It 'does not write a file when given an empty FQDN list' {
        $targetFile = Join-Path $TestDrive 'empty.txt'
        { Export-GSAEdgeAddresses -fqdnList @() -filePath $targetFile } | Should -Not -Throw
        Test-Path $targetFile | Should -Be $false
    }

    It 'uses the GSA client endpoints and a default file path when called without parameters' {
        Mock -ModuleName GSAClientDiagnosticsToolkit Get-GSAEndpoints {
            [PSCustomObject]@{ MainEndpoints = @('edge1.example.com', 'edge2.example.com') }
        }
        Push-Location $TestDrive
        try {
            Export-GSAEdgeAddresses
            Get-Content (Join-Path $TestDrive 'GSAEdgeAddresses.txt') | Should -Be @('edge1.example.com', 'edge2.example.com')
        }
        finally {
            Pop-Location
        }
    }

    It 'does not throw when no file path is specified' {
        { Export-GSAEdgeAddresses -fqdnList @('edge1.example.com') -filePath $null } | Should -Not -Throw
    }
}

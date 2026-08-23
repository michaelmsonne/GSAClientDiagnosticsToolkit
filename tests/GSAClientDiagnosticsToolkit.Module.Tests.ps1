BeforeAll {
    $script:ModuleName = 'GSAClientDiagnosticsToolkit'
    $script:ModuleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\GSAClientDiagnosticsToolkit.psd1'
    Import-Module $script:ModuleManifestPath -Force
}

AfterAll {
    Remove-Module $script:ModuleName -Force -ErrorAction SilentlyContinue
}

Describe 'Module manifest' {
    It 'passes Test-ModuleManifest validation' {
        { Test-ModuleManifest -Path $script:ModuleManifestPath -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Exported functions' {
    BeforeDiscovery {
        $manifest = Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\src\GSAClientDiagnosticsToolkit.psd1')
        $script:ExpectedFunctionNames = $manifest.FunctionsToExport
    }

    It 'exports exactly the functions listed in FunctionsToExport' {
        $expected = (Import-PowerShellDataFile -Path $script:ModuleManifestPath).FunctionsToExport
        $actual = (Get-Command -Module $script:ModuleName).Name
        Compare-Object -ReferenceObject $expected -DifferenceObject $actual | Should -BeNullOrEmpty
    }

    It 'has a .SYNOPSIS help entry for <_>' -ForEach $script:ExpectedFunctionNames {
        (Get-Help $_).Synopsis | Should -Not -BeNullOrEmpty
    }
}

Describe 'PSScriptAnalyzer' -Skip:(-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    BeforeAll {
        Import-Module PSScriptAnalyzer
        $script:SourceRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\src'
    }

    It 'has no Error-severity findings' {
        $results = Invoke-ScriptAnalyzer -Path $script:SourceRoot -Recurse -Severity Error
        $results | Should -BeNullOrEmpty
    }
}

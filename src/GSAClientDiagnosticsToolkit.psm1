#======================================================================================================================
# THIS CODE SAMPLE IS PROVIDED "AS IS," WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This sample is not supported under any standard support program or service. You assume all risk arising from its use
# or performance, and from the use of its documentation. In no event shall the author, contributors, or anyone involved
# in creating, producing, or delivering this sample be liable for any damages (including lost profits, business
# interruption, loss of business information, or other pecuniary loss) arising from its use or inability to use it,
# even if advised of the possibility of such damages.
#======================================================================================================================

#region Module State - shared across all Private and Public functions

$script:ModuleVer                 = "1.0.0"
$script:GSAFwdProfileRegistryPath = "HKLM:\SOFTWARE\Microsoft\Global Secure Access Client"
$script:LogLevel                  = "INFO"
# Default log path so any function (not just Invoke-GSAClientConnectivityCheck) writes to a file.
# Use the user's temp folder rather than the current working directory, since the current directory
# (e.g. C:\Windows\system32 for a default elevated PowerShell session) may not be writable.
$script:LogFilePath               = Join-Path -Path $env:TEMP -ChildPath "GSAClientDiagnosticsToolkit.log"
$script:LogLockObject             = New-Object System.Object

#endregion

# Dot-source Private helpers (not exported)
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction Stop |
    ForEach-Object { . $_.FullName }

# Dot-source Public functions and collect names for export
$_publicFiles = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction Stop
$_publicFiles | ForEach-Object { . $_.FullName }

Export-ModuleMember -Function $_publicFiles.BaseName

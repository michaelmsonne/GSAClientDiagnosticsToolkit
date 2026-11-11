#======================================================================================================================
# THIS CODE-SAMPLE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT
# LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
#
# This sample is not supported under any standard support program or service. The code sample is provided
# AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation,
# any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the
# use or performance of the sample and documentation remains with you. In no event shall the author, its contributors, or
# anyone else involved in the creation, production, or delivery of the script be liable for any damages whatsoever
# (including, without limitation, damages for loss of business profits, business interruption, loss of business
# information, or other pecuniary loss) arising out of the use of or inability to use the sample or documentation,
# even if Microsoft has been advised of the possibility of such damages.
#======================================================================================================================

#region Module State - shared across all Private and Public functions

$script:ModuleVer                 = "1.0.0"
$script:GSAFwdProfileRegistryPath = "HKLM:\SOFTWARE\Microsoft\Global Secure Access Client"
$script:LogLevel                  = "INFO"
# Default log path so any function (not just Invoke-GSAClientConnectivityCheck) writes to a file
$script:LogFilePath               = Join-Path -Path $PWD.ProviderPath -ChildPath "GSAClientDiagnosticsToolkit.log"
$script:LogLockObject             = New-Object System.Object

#endregion

# Dot-source Private helpers (not exported)
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction Stop |
    ForEach-Object { . $_.FullName }

# Dot-source Public functions and collect names for export
$_publicFiles = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction Stop
$_publicFiles | ForEach-Object { . $_.FullName }

Export-ModuleMember -Function $_publicFiles.BaseName

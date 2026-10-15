#
# Module manifest for GSAClientDiagnosticsToolkit
#
@{
    # Module identity
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f7c2b1-4d89-4e6a-b012-5f8c9d3e7a21'
    Author            = 'Michael Morten Sonne'
    CompanyName       = 'blog.sonnes.cloud'
    Copyright         = '(c) Michael Morten Sonne. All rights reserved.'
    Description       = 'Runs connectivity, proxy, health probe and mTLS checks for the Global Secure Access (GSA) Client.'

    # Minimum PowerShell version required
    PowerShellVersion = '5.1'

    # Windows PowerShell only - relies on registry, dsregcmd, netsh, and Get-NetAdapter
    CompatiblePSEditions = @('Desktop')

    # Module file
    RootModule        = 'GSAClientDiagnosticsToolkit.psm1'

    # Custom output formatting (e.g. Get-GSAEndpoints)
    FormatsToProcess  = @('GSAClientDiagnosticsToolkit.format.ps1xml')

    # Online help landing page for Get-Help -Online
    HelpInfoURI       = 'https://github.com/michaelmsonne/GSAClientDiagnosticsToolkit/blob/main/README.md'

    # Functions to export (controls public API surface)
    FunctionsToExport = @(
        'Invoke-GSAClientConnectivityCheck',
        'Get-GSAEndpoints',
        'Get-GSAAppProtectionExclusionServicePrincipals',
        'Export-GSAEdgeAddresses',
        'Test-GSAServiceStatus',
        'Test-DeviceEntraStatus',
        'Test-GSAPrimaryRefreshToken',
        'Test-GSAForwardingProfileRegistry',
        'Test-GSAForwardingProfileTimestamp',
        'Test-GSASecureDnsStatus',
        'Test-GSAIPv6Status',
        'Test-GSASyntheticRoutes',
        'Test-GSAPrivateDnsResolver',
        'Test-GSAVpnSplitDnsInteroperability',
        'Test-GSAEventLog',
        'Test-InternetConnectivity',
        'Test-DnsResolution',
        'Test-GSATenantInternetDnsResolution',
        'Test-TLSConnection',
        'Test-mTLSConnection',
        'Test-ProxyDetection',
        'Test-EntraIDConnectivity',
        'Test-EntraIDUserAuthentication',
        'Test-GSADiagnosticUriConnectivity',
        'Test-GSAPrivateAccessRule',
        'Test-GSAPrivateAccessTunnel',
        'Test-GSAForwardingProfileAssignment',
        'Test-GSAClientProfileConnectivity',
        'Test-GSAPrivateAccessApplicationSegment',
        'Test-GSAPrivateAccessApplication',
        'Test-GSAIntelligentLocalAccessConfiguration',
        'Test-GSAAuthCertificate',
        'Export-GSAAuthCertificate',
        'Repair-GSAAuthCertificate'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Test-EntraIDUserAuthentication requires MSAL.PS; listed as optional since it is not part of the main check suite
    # RequiredModules = @('MSAL.PS')

    PrivateData = @{
        PSData = @{
            Tags         = @('GSA', 'GlobalSecureAccess', 'Connectivity', 'Diagnostics', 'Entra', 'mTLS', 'Microsoft')
            ProjectUri   = 'https://github.com/michaelmsonne/GSAClientDiagnosticsToolkit'
            LicenseUri   = 'https://github.com/michaelmsonne/GSAClientDiagnosticsToolkit/blob/main/LICENSE'
            ReleaseNotes = 'https://github.com/michaelmsonne/GSAClientDiagnosticsToolkit/releases'
        }
    }
}

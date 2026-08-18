#
# Module manifest for GSAClientConnectivityChecker
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

    # Module file
    RootModule        = 'GSAClientConnectivityChecker.psm1'

    # Functions to export (controls public API surface)
    FunctionsToExport = @(
        'Invoke-GSAClientConnectivityCheck',
        'Get-GSAEndpoints',
        'Save-EdgeAddresses',
        'Test-GSAServiceStatus',
        'Test-DeviceEntraStatus',
        'Test-GSAPrimaryRefreshToken',
        'Test-GSAForwardingProfileRegistry',
        'Test-GSAForwardingProfileTimestamp',
        'Test-GSASecureDnsStatus',
        'Test-GSAIPv6Status',
        'Test-GSASyntheticRoutes',
        'Test-GSAPrivateDnsResolver',
        'Test-GSAEventLog',
        'Test-InternetConnectivity',
        'Test-DnsResolution',
        'Test-TLSConnection',
        'Test-mTLSConnection',
        'Test-ProxyDetection',
        'Test-EntraIDConnectivity',
        'Test-EntraIDUserAuthN',
        'Test-DiagnosticUris'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Test-EntraIDUserAuthN requires MSAL.PS; listed as optional since it is not part of the main check suite
    # RequiredModules = @('MSAL.PS')

    PrivateData = @{
        PSData = @{
            Tags         = @('GSA', 'GlobalSecureAccess', 'Connectivity', 'Diagnostics', 'Entra', 'mTLS', 'Microsoft')
            ProjectUri   = 'https://github.com/michaelmsonne/GSAClientConnectivityChecker'
            ReleaseNotes = 'Initial module release.'
        }
    }
}

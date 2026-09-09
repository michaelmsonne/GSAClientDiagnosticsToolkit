# Changelog

All notable changes to this project are documented in this file. Dates reflect the commit history in this repository.

## [Unreleased] - xx-xx-xxxx

### Added

- Microsoft Graph-based checks, adapted to this module's conventions:
  - `Test-GSAForwardingProfileAssignment` - tenant onboarding, forwarding profile enablement, and user/group assignment.
  - `Test-GSAClientProfileConnectivity` - local edge/diagnostic connectivity per forwarding profile channel (`m365`/`private`/`internet`), testing all three by default when `-ProfileType` is omitted.
  - `Test-GSAPrivateAccessApplicationSegment` - Private Access application enablement, assignment, and application segment (FQDN/IP/port/protocol) matching via Graph.
  - `Test-GSAPrivateAccessApplication` - end-to-end Private Access application check combining the segment check with a live tunnel test.
- Automatic interactive `Connect-MgGraph` sign-in fallback (via the optional `Microsoft.Graph.Authentication` module) when `-AccessToken` isn't supplied to the Graph-based checks, reusing any already-active session.
- Local/offline Private Access checks: `Test-GSAPrivateAccessRule` (matches a target FQDN/IP + port + protocol against the locally cached forwarding profile's rules) and `Test-GSAPrivateAccessTunnel` (verifies a live tunnel connection resolves to a synthetic `6.6.x.x` address and resolves via the GSA Private DNS resolver).
- `-PassThru` switch on the new Private Access and Graph-based functions so they stay silent by default and only return a `$true`/`$false` result when explicitly requested.
- `-LogLevel` parameter on public functions to override the module's logging verbosity per call.
- New connectivity tests: `Test-GSAPrimaryRefreshToken`, `Test-GSAForwardingProfileRegistry`, `Test-GSAForwardingProfileTimestamp`, `Test-GSAServiceStatus`, `Test-GSASecureDnsStatus`, `Test-GSAIPv6Status`, `Test-GSASyntheticRoutes`, `Test-GSAPrivateDnsResolver`, `Test-GSAEventLog`, `Test-DeviceEntraStatus`, and `Test-EntraIDConnectivity`.
- Converted the original monolithic `GSAClientDiagnosticsToolkit.ps1` script into a proper PowerShell module (`src/GSAClientDiagnosticsToolkit.psd1`/`.psm1`) with `Public`/`Private` folder structure and `Invoke-GSAClientConnectivityCheck` as the orchestrator.
- README documentation covering installation, quick start, all public functions, log levels, and usage examples.
- Module manifest metadata: `LicenseUri`, `CompatiblePSEditions`, `HelpInfoURI`, and `ReleaseNotes`.
- Pester test suite (`tests/Public`, `tests/Private`) covering the module manifest/export consistency, private helper logic, and public function behavior via mocked dependencies.
- `Test-GSAAuthCertificate` - checks whether a valid GSA mTLS authentication certificate (subject ending in `gsa.client`) exists in the LocalMachine\My store and hasn't expired, mirroring the client's built-in "Authentication certificate exists"/"Authentication certificate is valid" Health check tests.
- `Export-GSAAuthCertificate` - read-only backup of the GSA authentication certificate(s) (password-protected `.pfx` with the private key when exportable, otherwise a public-key-only `.cer`), usable standalone or as the backup step reused by `Repair-GSAAuthCertificate`.
- `Repair-GSAAuthCertificate` - remediation for a missing/invalid authentication certificate: always backs up the certificate first via `Export-GSAAuthCertificate`, requires two separate confirmations before deleting it (standard `-WhatIf`/`-Confirm` plus typing the exact thumbprint), clears the `CertCommonName` registry value, and can optionally restart `GlobalSecureAccessEngineService` via `-RestartEngineService`.
- `Get-GSAAppProtectionExclusionServicePrincipals` - returns the known Global Secure Access-related service principals/app IDs to exclude in App Protection policies (based on field validation on Windows and iOS), and validates each App ID in-tenant via Microsoft Graph to report existence and current state.
- `Test-GSAIntelligentLocalAccessConfiguration` - checks Intelligent Local Access (ILA) Private Network definitions via Microsoft Graph (`networkAccess/privateNetworks`) for probe FQDNs that are publicly resolvable, and DNS server/expected IP addresses that are public rather than private (RFC1918) - a confirmed real-world root cause of GSA incorrectly bypassing Private Access traffic to a local connection for users who were never on the corporate network (e.g. on hotel/home Wi-Fi). Resolves each Private Network's associated App IDs to friendly display names (via the same `tags/Any` filter the Entra portal uses) and flags App IDs that no longer resolve to a known ZTNA/Quick Access application. Public resolvability is checked via DNS-over-HTTPS instead of a classic port-53 query, since the latter can be silently intercepted/answered by the local GSA client (WFP driver) or a router's own local DNS records; a resulting GSA synthetic `6.6.x.x` address is detected and reported as inconclusive rather than a false failure. Supports a `-FQDN` manual mode (with optional `-DnsServerAddress`/`-ExpectedIPAddress`) to check a single candidate FQDN without calling Microsoft Graph.

### Changed

- Refactored PowerShell scripts for improved readability and consistency.
- Enhanced logging and error handling across connectivity tests, including detailed DEBUG-level information for DNS chain retrieval, Entra ID status, GSA event log scanning, and service status checks.

### Fixed

- Incorrect `tenantId` reference in `Test-GSAForwardingProfileRegistry` logging.
- Noisy `Resolve-DnsName` output in `Test-GSAPrivateDnsResolver`.
- Missing/failed GSA service test result handling.
- `Select-Object -ExpandProperty` failing with "Property cannot be found" when Graph responses came back as `Hashtable` objects from `Invoke-MgGraphRequest` (as opposed to `PSCustomObject` from `Invoke-RestMethod`).

## Project history

- **2026-08-18** to **2026-08-20** - Converted the script into the `GSAClientDiagnosticsToolkit` PowerShell module and progressively added the Entra ID, Private Access, and Microsoft Graph checks described above + more.

- **2025-05-08** to **2025-05-09** - Initial standalone `GSAClientDiagnosticsToolkit.ps1` script: connectivity, proxy, health probe, and mTLS diagnostic checks for the Global Secure Access client, including log path error handling.

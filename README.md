# GSAClientConnectivityChecker

<p align="center">
  <a href="https://github.com/michaelmsonne/GSAClientConnectivityChecker/issues"><img alt="GitHub issues" src="https://img.shields.io/github/issues/michaelmsonne/GSAClientConnectivityChecker"></a>
  <a href="https://github.com/michaelmsonne/GSAClientConnectivityChecker/pulls"><img alt="GitHub pull requests" src="https://img.shields.io/github/issues-pr/michaelmsonne/GSAClientConnectivityChecker"></a>
  <a href="https://github.com/michaelmsonne/GSAClientConnectivityChecker"><img alt="Top language" src="https://img.shields.io/github/languages/top/michaelmsonne/GSAClientConnectivityChecker.svg"></a>
  <a href="https://github.com/michaelmsonne/GSAClientConnectivityChecker"><img alt="Code size" src="https://img.shields.io/github/languages/code-size/michaelmsonne/GSAClientConnectivityChecker.svg"></a><br>
  <a href="https://learn.microsoft.com/powershell/"><img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white"></a>
  <a href="https://learn.microsoft.com/windows/"><img alt="Platform" src="https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-yellow.svg"></a><br>
  <a href="https://www.linkedin.com/in/michaelmsonne/"><img alt="Made by" src="https://img.shields.io/static/v1?label=made%20by&message=Michael%20Morten%20Sonne&color=04D361"></a>
  <a href="https://github.com/michaelmsonne/GSAClientConnectivityChecker/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/michaelmsonne/GSAClientConnectivityChecker?style=social"></a>
  <a href="https://github.com/michaelmsonne/GSAClientConnectivityChecker/network/members"><img alt="GitHub forks" src="https://img.shields.io/github/forks/michaelmsonne/GSAClientConnectivityChecker?style=social"></a>
</p>

A PowerShell module that runs connectivity, proxy, health probe, and mTLS diagnostic checks for the **Microsoft Global Secure Access (GSA) Client**.

> [!IMPORTANT]
> Requires **PowerShell 5.1 or later**. Most checks must be run on a machine with the **Global Secure Access (GSA) Client** installed.

---

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Requirements](#requirements)
- [Installation](#installation)
- [Importing the Module](#importing-the-module)
- [Quick Start](#quick-start)
- [Public Functions](#public-functions)
- [Log Levels](#log-levels)
- [Examples](#examples)
- [Star This Project](#star-this-project)
- [Support](#support)
- [Disclaimer](#disclaimer)

---

## Overview

`GSAClientConnectivityChecker` automates end-to-end diagnostics for the Global Secure Access (GSA) Client on Windows. It covers:

- GSA Windows service health
- Entra ID device and PRT status
- Forwarding profile registry and timestamp validation
- DNS resolution for GSA edge addresses
- TLS and mTLS connectivity to GSA endpoints
- Proxy detection (system proxy, transparent proxy, authenticating proxy)
- Secure DNS and IPv6 status
- Synthetic routes and private DNS resolver
- Entra ID reachability
- GSA diagnostic URI connectivity
- GSA event log inspection

---

## Repository Structure

Outline of the repository's file contents, to help you navigate the codebase, tests, and related assets.

| File/folder | Description |
|---|---|
| `src/` | Module source code. |
| `src/GSAClientConnectivityChecker.psd1` | Module manifest (metadata, exported functions). |
| `src/GSAClientConnectivityChecker.psm1` | Root module file - dot-sources `Private`/`Public` and exports the public functions. |
| `src/Public/` | Exported public functions (one file per function, e.g. `Invoke-GSAClientConnectivityCheck.ps1`). |
| `src/Private/` | Internal helper functions used by the public functions, not exported. |
| `tests/` | Pester test suite, mirroring the `src/Public`/`src/Private` structure. |
| `docs/` | Reserved for additional documentation. |
| `GSAClientConnectivityChecker.ps1` | Legacy standalone script version, kept for reference/backward compatibility. |
| `CHANGELOG.md` | List of notable changes to the module. |
| `LICENSE` | The MIT license for this project. |
| `README.md` | This README file. |

---

## Requirements

| Requirement | Details |
|---|---|
| PowerShell | 5.1 or later |
| OS | Windows (GSA Client must be installed for some tests) |
| Elevation | Recommended - some checks (mTLS certificate access) require admin rights |
| Optional module | `MSAL.PS` - required only for `Test-EntraIDUserAuthN` |
| Optional module | `Microsoft.Graph.Authentication` - required only for the Graph-based checks below when you don't supply `-AccessToken` yourself |

---

## Installation

### Option A - Clone and import locally

```powershell
git clone https://github.com/michaelmsonne/GSAClientConnectivityChecker.git
Import-Module .\GSAClientConnectivityChecker\GSAClientConnectivityChecker.psd1
```

### Option B - Copy the folder to a module path

Copy the `GSAClientConnectivityChecker` folder to one of your `$env:PSModulePath` directories, for example:

```powershell
Copy-Item -Recurse .\GSAClientConnectivityChecker `
    "$env:USERPROFILE\Documents\PowerShell\Modules\GSAClientConnectivityChecker"
```

Then import it in any PowerShell session:

```powershell
Import-Module GSAClientConnectivityChecker
```

---

## Importing the Module

```powershell
# From the cloned/downloaded folder
Import-Module .\GSAClientConnectivityChecker.psd1

# Verify the module loaded and see all exported commands
Get-Command -Module GSAClientConnectivityChecker
```

---

## Quick Start

Run the full diagnostic suite with default settings:

```powershell
Import-Module .\GSAClientConnectivityChecker.psd1
Invoke-GSAClientConnectivityCheck
```

Run with verbose (DEBUG) logging and save the log to a custom path:

```powershell
Invoke-GSAClientConnectivityCheck -LogLevel DEBUG -BasePath C:\Logs
```

---

## Public Functions

> Most functions below also accept an optional `-LogLevel <string>` parameter (`ERROR`, `WARNING`, `INFO`, `DEBUG`, `SUCCESS`) that overrides the module's current logging verbosity for just that call.

### `Invoke-GSAClientConnectivityCheck`

Runs the complete diagnostic suite in sequence and produces a summary.

```powershell
Invoke-GSAClientConnectivityCheck [-LogLevel <string>] [-BasePath <string>] [-LogFileName <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `LogLevel` | `INFO` | Verbosity: `ERROR`, `WARNING`, `INFO`, `DEBUG`, `SUCCESS` |
| `BasePath` | Current directory | Directory where the log file is written |
| `LogFileName` | `GSAClientConnectivityChecker.log` | Name of the log file |

---

### `Get-GSAEndpoints`

Loads the GSA ForwardingProfile JSON from the registry and returns the list of edge addresses and diagnostic URIs.

```powershell
Get-GSAEndpoints [-RegistryValueName <string>]
```

---

### `Save-EdgeAddresses`

Saves a list of edge address FQDNs to a file.

```powershell
Save-EdgeAddresses -fqdnList <string[]> -filePath <string>
```

---

### `Test-GSAServiceStatus`

Verifies that all required Global Secure Access Windows services are in the **Running** state.

```powershell
Test-GSAServiceStatus [-LogLevel <string>]
```

Services checked: `GlobalSecureAccessTunnelingService`, `GlobalSecureAccessClientManagerService`, `GlobalSecureAccessEngineService`, `GlobalSecureAccessDriver`, and the forwarding profile service.

---

### `Test-DeviceEntraStatus`

Checks whether the device is Entra ID joined or registered.

```powershell
Test-DeviceEntraStatus [-LogLevel <string>]
```

---

### `Test-GSAPrimaryRefreshToken`

Verifies that a valid Primary Refresh Token (PRT) is present on the device.

```powershell
Test-GSAPrimaryRefreshToken [-LogLevel <string>]
```

---

### `Test-GSAForwardingProfileRegistry`

Validates that the GSA forwarding profile exists and is readable from the registry.

```powershell
Test-GSAForwardingProfileRegistry [-LogLevel <string>]
```

---

### `Test-GSAForwardingProfileTimestamp`

Checks the timestamp of the forwarding profile to detect stale configuration.

```powershell
Test-GSAForwardingProfileTimestamp [-LogLevel <string>]
```

---

### `Test-InternetConnectivity`

Tests basic internet reachability and inspects active network interfaces with default routes.

```powershell
Test-InternetConnectivity [-Websites <string[]>] [-DnsServers <string[]>] [-TimeoutMs <int>] [-LogLevel <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `Websites` | `www.google.com`, `www.microsoft.com` | Websites to test for reachability |
| `DnsServers` | `1.1.1.1`, `8.8.8.8`, `9.9.9.9` | DNS servers to test for reachability over UDP port 53 |
| `TimeoutMs` | `5000` | UDP receive timeout in milliseconds |

---

### `Test-ProxyDetection`

Detects outbound proxy configuration via system settings, transparent proxy HTTP headers, and HTTP 407 responses.

```powershell
Test-ProxyDetection [-TestUrlHttp <string>] [-TestUrlHttps <string>] [-TimeoutSec <int>] [-LogLevel <string>]
```

---

### `Test-GSASecureDnsStatus`

Checks whether the GSA Secure DNS feature is enabled and active.

```powershell
Test-GSASecureDnsStatus [-LogLevel <string>]
```

---

### `Test-GSAIPv6Status`

Reports the IPv6 status on the GSA tunnel adapter.

```powershell
Test-GSAIPv6Status [-LogLevel <string>]
```

---

### `Test-DnsResolution`

Resolves each FQDN in the provided list and logs the results.

```powershell
Test-DnsResolution -fqdnList <string[]> [-LogLevel <string>]
```

---

### `Test-TLSConnection`

Tests TLS (HTTPS) connectivity to each FQDN on port 443 and logs certificate details at DEBUG level.

```powershell
Test-TLSConnection -fqdnList <string[]> [-port <int>] [-LogLevel <string>]
```

---

### `Test-mTLSConnection`

Tests mTLS connectivity using GSA client certificates from the LocalMachine certificate store.

> Run as Administrator for full access to certificate private keys.

```powershell
Test-mTLSConnection -fqdnList <string[]> [-port <int>] [-LogLevel <string>]
```

---

### `Test-GSAAuthCertificate`

Checks whether a valid GSA mTLS authentication certificate (subject ending in `gsa.client`) exists in the LocalMachine\My certificate store and hasn't expired. Mirrors the client's built-in "Authentication certificate exists"/"Authentication certificate is valid" Health check tests. This test only applies to tenants with mTLS enabled - if mTLS isn't enabled, no certificate is expected.

```powershell
Test-GSAAuthCertificate [-PassThru] [-LogLevel <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `PassThru` | Off | Return the `$true`/`$false` test result instead of just logging it |

---

### `Repair-GSAAuthCertificate`

Backs up and removes the GSA mTLS authentication certificate so the client re-enrolls a new one - the documented fix when `Test-GSAAuthCertificate` fails. Always exports a backup first (`.pfx` with the private key when exportable, otherwise falls back to a public-key-only `.cer`), then requires **two separate confirmations** before deleting anything: the standard `-WhatIf`/`-Confirm` prompt, plus typing the certificate's exact thumbprint. Also clears the `CertCommonName` registry value so a new certificate is re-provisioned.

> [!WARNING]
> This is a destructive operation. Requires an elevated (Administrator) PowerShell session. Run `Repair-GSAAuthCertificate -WhatIf` first to preview what would happen.

```powershell
Repair-GSAAuthCertificate [-BackupPath <string>] [-RestartEngineService] [-PassThru] [-LogLevel <string>] [-WhatIf] [-Confirm]
```

| Parameter | Default | Description |
|---|---|---|
| `BackupPath` | Current directory | Directory to export the certificate backup(s) to before deletion |
| `RestartEngineService` | Off | Restart `GlobalSecureAccessEngineService` afterwards so a new certificate is provisioned immediately |
| `PassThru` | Off | Return the `$true`/`$false` result instead of just logging it |

---

### `Test-EntraIDConnectivity`

Tests network reachability of Entra ID endpoints.

```powershell
Test-EntraIDConnectivity [-Endpoints <string[]>] [-Timeout <int>] [-LogLevel <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `Endpoints` | Core Entra ID/Graph/device-registration URLs | Entra ID endpoint URLs to test |
| `Timeout` | `15` | HTTP request timeout in seconds |

---

### `Test-EntraIDUserAuthN`

Performs an interactive MSAL token acquisition against Entra ID. Requires the `MSAL.PS` module.

```powershell
Install-Module MSAL.PS
Test-EntraIDUserAuthN
```

---

### `Test-DiagnosticUris`

Tests connectivity to the GSA per-channel diagnostic URIs extracted from the forwarding profile.

```powershell
Test-DiagnosticUris -DiagnosticUris <string[]> [-LogLevel <string>]
```

---

### `Test-GSASyntheticRoutes`

Verifies that expected synthetic routes injected by the GSA tunnel are present in the routing table.

```powershell
Test-GSASyntheticRoutes [-LogLevel <string>]
```

---

### `Test-GSAPrivateDnsResolver`

Tests whether the GSA Private DNS Resolver is active and responding.

```powershell
Test-GSAPrivateDnsResolver [-LogLevel <string>]
```

---

### `Test-GSAPrivateAccessRule`

Checks whether the locally cached forwarding profile's Private Access rules permit a given target FQDN/IP, port, and protocol - mirroring the client-side rule matching the GSA client performs itself. This is a fully local/offline check (registry only); it does not call Microsoft Graph or require sign-in. By default nothing is returned (only logged); pass `-PassThru` to get the `$true`/`$false` result back for scripting.

```powershell
Test-GSAPrivateAccessRule -FQDNorIP <string> -Port <int> -Protocol <TCP|UDP> [-RegistryValueName <string>] [-PassThru] [-LogLevel <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `FQDNorIP` | *(required)* | Target FQDN or IPv4 address to test |
| `Port` | *(required)* | Target TCP/UDP port number |
| `Protocol` | *(required)* | `TCP` or `UDP` |
| `RegistryValueName` | `ForwardingProfile` | Registry value containing the GSA JSON policy |
| `PassThru` | Off | Return the `$true`/`$false` test result instead of just logging it |

---

### `Test-GSAPrivateAccessTunnel`

Opens a live TCP connection to the target FQDN/IP and port to verify traffic is actually tunneled through GSA. For FQDN targets, confirms the connection resolved to a synthetic `6.6.x.x` address and resolves the internal address via the GSA Private DNS resolver (`6.6.255.254`). UDP targets cannot be tunnel-tested this way and are reported as a warning only. By default nothing is returned (only logged); pass `-PassThru` to get the `$true`/`$false` result back for scripting.

```powershell
Test-GSAPrivateAccessTunnel -FQDNorIP <string> -Port <int> -Protocol <TCP|UDP> [-PassThru] [-LogLevel <string>]
```

---

### `Test-GSAClientProfileConnectivity`

Confirms the locally cached forwarding profile contains a channel for the requested profile type(s) (`m365`/`private`/`internet`), tests TCP connectivity to each channel's primary edge (falling back to the secondary edge), and confirms each channel's diagnostic endpoint responds with HTTP 200 and body `pong`. This is a fully local/offline check; it does not call Microsoft Graph.

```powershell
Test-GSAClientProfileConnectivity [-ProfileType <m365|private|internet>[,...]] [-RegistryValueName <string>] [-PassThru] [-LogLevel <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `ProfileType` | All three (`m365`, `private`, `internet`) | One or more of `m365`, `private`, `internet` to test |
| `RegistryValueName` | `ForwardingProfile` | Registry value containing the GSA JSON policy |
| `PassThru` | Off | Return the combined `$true`/`$false` test result (across all tested profiles) instead of just logging it |

---

> The three functions below call Microsoft Graph. Pass an access token via `-AccessToken` (e.g. acquired via `Test-EntraIDUserAuthN`/`MSAL.PS`, or your own Graph sign-in) with the `NetworkAccess.Read.All`, `Application.Read.All`, `Directory.Read.All`, and `User.Read.All` delegated permissions. If you omit `-AccessToken`, the module automatically prompts an interactive sign-in via `Connect-MgGraph` (requires the `Microsoft.Graph.Authentication` module) and reuses any already-active Graph session for subsequent calls, so you're only prompted once per session.

### `Test-GSAForwardingProfileAssignment`

Checks via Microsoft Graph that the tenant is onboarded to Global Secure Access, that the requested forwarding profile (`m365`/`private`/`internet`) is enabled, and that the target user is assigned - directly or via group membership - to that profile's enterprise application.

```powershell
Test-GSAForwardingProfileAssignment [-AccessToken <string>] -ProfileType <m365|private|internet> [-UserPrincipalName <string>] [-PassThru] [-LogLevel <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `AccessToken` | Prompts `Connect-MgGraph` sign-in | Microsoft Graph access token |
| `ProfileType` | *(required)* | `m365`, `private`, or `internet` |
| `UserPrincipalName` | Current signed-in user (`whoami /upn`) | UPN of the user to check assignment for |
| `PassThru` | Off | Return the `$true`/`$false` test result instead of just logging it |

---

### `Test-GSAPrivateAccessApplicationSegment`

Checks via Microsoft Graph that a Private Access application is enabled, the user is assigned, and the target FQDN/IP + port + protocol is covered by one of its application segments.

```powershell
Test-GSAPrivateAccessApplicationSegment [-AccessToken <string>] -AppId <string> -FQDNorIP <string> -Port <int> -Protocol <TCP|UDP> [-UserPrincipalName <string>] [-PassThru] [-LogLevel <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `AccessToken` | Prompts `Connect-MgGraph` sign-in | Microsoft Graph access token |
| `AppId` | *(required)* | The Private Access application's (client) App ID |
| `FQDNorIP` | *(required)* | Target FQDN or IPv4 address to test |
| `Port` | *(required)* | Target TCP/UDP port number |
| `Protocol` | *(required)* | `TCP` or `UDP` |
| `UserPrincipalName` | Current signed-in user (`whoami /upn`) | UPN of the user to check assignment for |
| `PassThru` | Off | Return the `$true`/`$false` test result instead of just logging it |

---

### `Test-GSAPrivateAccessApplication`

Full end-to-end Private Access application check: confirms "Enable access with Global Secure Access client" is turned on for the application, runs `Test-GSAPrivateAccessApplicationSegment` to validate the Entra-side configuration, and then runs `Test-GSAPrivateAccessTunnel` to verify the traffic actually tunnels through the GSA client.

```powershell
Test-GSAPrivateAccessApplication [-AccessToken <string>] -AppId <string> -FQDNorIP <string> -Port <int> -Protocol <TCP|UDP> [-UserPrincipalName <string>] [-PassThru] [-LogLevel <string>]
```

| Parameter | Default | Description |
|---|---|---|
| `AccessToken` | Prompts `Connect-MgGraph` sign-in | Microsoft Graph access token |
| `AppId` | *(required)* | The Private Access application's (client) App ID |
| `FQDNorIP` | *(required)* | Target FQDN or IPv4 address to test |
| `Port` | *(required)* | Target TCP/UDP port number |
| `Protocol` | *(required)* | `TCP` or `UDP` |
| `UserPrincipalName` | Current signed-in user (`whoami /upn`) | UPN of the user to check assignment for |
| `PassThru` | Off | Return the `$true`/`$false` test result instead of just logging it |

---

### `Test-GSAEventLog`

Reads the GSA event log and reports recent errors and warnings.

```powershell
Test-GSAEventLog [-LogLevel <string>]
```

---

## Log Levels

| Level | What is logged |
|---|---|
| `ERROR` | Failures only |
| `WARNING` | Failures and warnings |
| `INFO` | Normal operational messages (default) |
| `SUCCESS` | Successful check confirmations |
| `DEBUG` | Everything, including certificate chains and raw registry values |

---

## Examples

```powershell
# Full check with default INFO logging
Invoke-GSAClientConnectivityCheck

# Full check with DEBUG output saved to C:\Logs
Invoke-GSAClientConnectivityCheck -LogLevel DEBUG -BasePath C:\Logs

# Full check, only log errors and warnings
Invoke-GSAClientConnectivityCheck -LogLevel WARNING

# Run individual checks
Test-GSAServiceStatus
Test-DeviceEntraStatus
Test-mTLSConnection -fqdnList (Get-GSAEndpoints).MainEndpoints

# Save the current edge addresses to a file
$endpoints = Get-GSAEndpoints
Save-EdgeAddresses -fqdnList $endpoints.MainEndpoints -filePath C:\Temp\edges.txt

# Check whether a specific Private Access target/port/protocol is allowed locally,
# then verify it actually tunnels through the GSA client
Test-GSAPrivateAccessRule -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP
Test-GSAPrivateAccessTunnel -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP

# Same checks, but capture the pass/fail result for scripting instead of just logging it
if (Test-GSAPrivateAccessRule -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP -PassThru) {
    Write-Host 'Rule allows this target'
}

# Test a specific channel's edge/diagnostic connectivity locally (no sign-in required)
Test-GSAClientProfileConnectivity -ProfileType private

# Or test all three channels (m365, private, internet) at once
Test-GSAClientProfileConnectivity

# Graph-based checks - by default prompts an interactive Connect-MgGraph sign-in the first time
# (requires the Microsoft.Graph.Authentication module); reuses the session on subsequent calls
Test-GSAForwardingProfileAssignment -ProfileType private
Test-GSAPrivateAccessApplicationSegment -AppId <appId> -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP
Test-GSAPrivateAccessApplication -AppId <appId> -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP

# Or pass your own access token instead (e.g. via Test-EntraIDUserAuthN + MSAL.PS)
Install-Module MSAL.PS
$token = (Get-MsalToken -ClientId '<your-client-id>' -Scopes 'https://graph.microsoft.com/.default').AccessToken
Test-GSAForwardingProfileAssignment -AccessToken $token -ProfileType private
```

---

## Star This Project

If `GSAClientConnectivityChecker` helps you troubleshoot Global Secure Access, please consider giving it a star! ⭐

---

## Support

This project is open-source and I invite everybody who can and will to contribute, but I cannot provide any formal support since this was created as a personal/hobby project, with the best intentions in mind. For commercial support, please reach out on LinkedIn so we can discuss the possibilities.

<a href="https://www.buymeacoffee.com/sonnes" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 30px !important;width: 117px !important;"></a>

Reach out to the maintainer at one of the following places:

- [GitHub Issues](https://github.com/michaelmsonne/GSAClientConnectivityChecker/issues) - for bugs and feature requests
- [LinkedIn](https://www.linkedin.com/in/michaelmsonne/) - for commercial inquiries
- The email listed on the [GitHub profile](https://github.com/michaelmsonne)

---

## Disclaimer

This module is provided **"AS IS"** without warranty of any kind. It is not supported under any Microsoft standard support program or service. Use at your own risk.

Author: Michael Morten Sonne - [blog.sonnes.cloud](https://blog.sonnes.cloud)
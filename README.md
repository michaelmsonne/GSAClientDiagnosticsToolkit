# GSAClientConnectivityChecker

A PowerShell module that runs connectivity, proxy, health probe, and mTLS diagnostic checks for the **Microsoft Global Secure Access (GSA) Client**.

> Requires PowerShell 5.1 or later. Most checks require the script to run on a machine with the GSA Client installed.

---

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Importing the Module](#importing-the-module)
- [Quick Start](#quick-start)
- [Public Functions](#public-functions)
- [Log Levels](#log-levels)
- [Examples](#examples)
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

## Requirements

| Requirement | Details |
|---|---|
| PowerShell | 5.1 or later |
| OS | Windows (GSA Client must be installed) |
| Elevation | Recommended - some checks (mTLS certificate access) require admin rights |
| Optional module | `MSAL.PS` - required only for `Test-EntraIDUserAuthN` |

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
```

---

## Disclaimer

This module is provided **"AS IS"** without warranty of any kind. It is not supported under any Microsoft standard support program or service. Use at your own risk.

Author: Michael Morten Sonne - [blog.sonnes.cloud](https://blog.sonnes.cloud)
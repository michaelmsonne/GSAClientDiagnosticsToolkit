function Test-GSAIntelligentLocalAccessConfiguration {
    <#
.SYNOPSIS
    Checks Intelligent Local Access (ILA) Private Network definitions in Entra for a misconfiguration
    that can cause GSA to incorrectly bypass Private Access traffic to a local/direct connection when
    the client is NOT actually on the expected corporate network.
.DESCRIPTION
    Retrieves all Private Network definitions via Microsoft Graph (networkAccess/privateNetworks) and,
    for each DNS-based network identification, checks:
        1. Whether the probe FQDN (fqdnToResolve) is publicly resolvable (has a public DNS record).
           A publicly resolvable probe FQDN defeats the purpose of the corporate-network detection,
           since it no longer proves the client is actually inside the corporate network - this was a
           real-world root cause reported by the community, where GSA attempted (and failed) to bypass
           Private Access traffic locally for users on hotel/home networks who were never on-premises.
        2. Whether the DNS server address(es) used for the probe are private/internal (RFC1918)
           addresses rather than public/routable ones - a public DNS server can be queried from any
           network, undermining the "only reachable from inside the corporate network" assumption.
        3. Whether the expected IP resolution(s) for the probe are private/internal addresses, as
           documented by Microsoft for Private Network identification.
    Each Private Network's associated application IDs are resolved to friendly display names (via the
    same tags/Any filter the Entra portal uses to list ZTNA/Quick Access apps) for more actionable
    logging, and any App ID that no longer resolves to a known app is flagged as possibly stale.
    This is an Entra/Graph configuration check only; it does not require the GSA client to be
    installed and can be run from any machine with Graph access.

    Caveat: plain DNS queries (even ones aimed at an explicit public server IP) can be transparently
    intercepted and answered locally - by the GSA client's own WFP driver for any FQDN it tunnels, or by
    a home/office router with its own local DNS records (e.g. a UniFi "Host (A)" record) - which would
    make a naive public-resolvability check unreliable. To avoid this, the probe FQDN is checked via
    DNS-over-HTTPS (DoH): an HTTPS request to a public resolver's API rather than a classic port-53
    lookup, which isn't subject to either kind of interception.
.PARAMETER AccessToken
    A Microsoft Graph access token with NetworkAccess.Read.All and Application.Read.All permissions.
    If omitted, an interactive Connect-MgGraph sign-in is triggered automatically (requires the
    Microsoft.Graph.Authentication module), reusing any already-active Graph session.
.PARAMETER PublicDnsServer
    The DNS-over-HTTPS (DoH) JSON API endpoint used to check whether a probe FQDN is publicly
    resolvable (default: https://dns.google/resolve).
.PARAMETER PassThru
    Return the $true/$false test result. By default nothing is returned - only logged.
.EXAMPLE
    Test-GSAIntelligentLocalAccessConfiguration
.EXAMPLE
    Test-GSAIntelligentLocalAccessConfiguration -AccessToken $token -PassThru
#>
    [CmdletBinding()]
    param (
        [string]$AccessToken,
        [string]$PublicDnsServer = "https://dns.google/resolve",
        [switch]$PassThru,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    Write-Log "Retrieving Intelligent Local Access Private Network definitions via Microsoft Graph..." "INFO"
    try {
        $result = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/beta/networkAccess/privateNetworks"
    }
    catch {
        Write-Log "Failed to retrieve Private Networks via Microsoft Graph: $_" "ERROR"
        if ($PassThru) { return $false }
        return
    }

    $privateNetworks = @($result.value)
    if ($privateNetworks.Count -eq 0) {
        Write-Log "No Private Networks (Intelligent Local Access) are configured in this tenant." "INFO"
        if ($PassThru) { return $true }
        return
    }

    $appDisplayNames = @{}
    try {
        $appFilter = "tags/Any(x:x eq 'IsAccessibleViaZTNAClient') or tags/Any(x:x eq 'NetworkAccessQuickAccessApplication')"
        $appsResult = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/beta/applications?`$filter=$([uri]::EscapeDataString($appFilter))&`$select=appId,displayName&`$top=999"
        foreach ($app in @($appsResult.value)) {
            if ($app.appId) { $appDisplayNames[$app.appId] = $app.displayName }
        }
    }
    catch {
        Write-Log "Failed to resolve Private Access/Quick Access application display names via Microsoft Graph: $_" "DEBUG"
    }

    $allTestsPassed = $true

    foreach ($network in $privateNetworks) {
        $networkName = $network.name
        $appIds = @($network.appIds) | Where-Object { $_ }
        $appNames = $appIds | ForEach-Object { if ($appDisplayNames.ContainsKey($_)) { $appDisplayNames[$_] } else { $_ } }
        Write-Log "Checking Private Network '$networkName' (target app(s): $($appNames -join ', '))..." "INFO"

        if ($appDisplayNames.Count -gt 0) {
            $unresolvedAppIds = $appIds | Where-Object { -not $appDisplayNames.ContainsKey($_) }
            foreach ($unresolvedAppId in $unresolvedAppIds) {
                Write-Log "Private Network '$networkName' references App ID '$unresolvedAppId', which is not a currently enabled ZTNA/Quick Access application - it may have been deleted or disabled." "WARNING"
            }
        }

        $identifications = @($network.networkIdentifications)
        if ($identifications.Count -eq 0) {
            Write-Log "Private Network '$networkName' has no network identification configured." "WARNING"
            $allTestsPassed = $false
            continue
        }

        foreach ($identification in $identifications) {
            $fqdn = $identification.fqdnToResolve.value
            $serverAddresses = @($identification.serverAddresses) | ForEach-Object { $_.value } | Where-Object { $_ }
            $expectedIPs = @($identification.expectedIpResolutions) | ForEach-Object { $_.value } | Where-Object { $_ }

            if (-not $fqdn) {
                Write-Log "Private Network '$networkName' has an identification entry with no probe FQDN configured." "WARNING"
                $allTestsPassed = $false
                continue
            }

            # 1. The probe FQDN must NOT be resolvable via a public DNS resolver - if it is, corporate-network
            #    detection can be satisfied from anywhere, causing GSA to falsely bypass traffic locally.
            #    Uses DNS-over-HTTPS rather than a classic port-53 query, since the latter can be silently
            #    intercepted/answered by the local GSA client or a router's own local DNS records.
            $publiclyResolvable = $false
            $publicIPs = @()
            try {
                $dohUri = "$PublicDnsServer`?name=$([uri]::EscapeDataString($fqdn))&type=A"
                $dohResponse = Invoke-RestMethod -Uri $dohUri -Headers @{ Accept = 'application/dns-json' } -ErrorAction Stop
                if ($dohResponse.Status -eq 0) {
                    # Status 0 (NOERROR) alone doesn't guarantee an A record exists - a NODATA response
                    # (e.g. only an Authority/SOA section, no Answer) means the zone exists but this
                    # name doesn't resolve publicly, so only a non-empty Answer counts as resolvable.
                    $publicIPs = @($dohResponse.Answer | Where-Object { $_.type -eq 1 } | Select-Object -ExpandProperty data -ErrorAction SilentlyContinue)
                    $publiclyResolvable = $publicIPs.Count -gt 0
                }
                elseif ($dohResponse.Status -ne 3) {
                    # Status 3 (NXDOMAIN) simply means "not resolvable" - anything else is inconclusive
                    Write-Log "Could not determine public resolvability of '$fqdn' via DNS-over-HTTPS ($PublicDnsServer): DNS status code $($dohResponse.Status)." "WARNING"
                }
            }
            catch {
                Write-Log "Could not determine public resolvability of '$fqdn' via DNS-over-HTTPS ($PublicDnsServer): $_" "WARNING"
            }

            if ($publiclyResolvable) {
                # A GSA-only device could still return its own synthetic 6.6.x.x address if the DoH provider
                # itself happened to be covered by a Private Access rule - vanishingly unlikely, but checked
                # anyway as defense-in-depth so this never produces a false failure.
                $syntheticIPs = @($publicIPs | Where-Object { $_ -like '6.6.*' })
                if ($syntheticIPs.Count -gt 0 -and $syntheticIPs.Count -eq $publicIPs.Count) {
                    Write-Log "Private Network '$networkName' probe FQDN '$fqdn' resolved to a GSA synthetic address ($($syntheticIPs -join ', ')) - the local GSA client is intercepting this query, so public resolvability can't be verified from this device." "WARNING"
                    Write-Log "Recommended action: Re-run this check from a device without the GSA client active for '$fqdn' (e.g. temporarily disable Private Access, or use a machine that doesn't have it installed) to get a trustworthy result." "WARNING"
                }
                else {
                    $ipInfo = if ($publicIPs.Count -gt 0) { " (resolves to $($publicIPs -join ', '))" } else { "" }
                    Write-Log "Private Network '$networkName' probe FQDN '$fqdn' is PUBLICLY resolvable via DNS-over-HTTPS$ipInfo." "ERROR"
                    Write-Log "Recommended action: Use an FQDN for '$networkName' that only resolves on your internal/corporate DNS servers (no public DNS record). A publicly resolvable probe FQDN defeats corporate-network detection and can cause GSA to incorrectly bypass Private Access traffic locally for users who are NOT on the corporate network (a confirmed real-world root cause of client connectivity failures on hotel/home networks)." "WARNING"
                    $allTestsPassed = $false
                }
            }
            else {
                Write-Log "Private Network '$networkName' probe FQDN '$fqdn' is not publicly resolvable - OK." "SUCCESS"
            }

            # 2. The DNS server(s) used for the probe should be private/internal addresses only.
            foreach ($serverAddress in $serverAddresses) {
                if (-not (Test-GSAIsPrivateIPv4 -IPAddress $serverAddress)) {
                    Write-Log "Private Network '$networkName' uses a public/non-RFC1918 DNS server address ($serverAddress) for corporate-network detection." "ERROR"
                    Write-Log "Recommended action: Configure an internal DNS server address for '$networkName' that is only reachable from inside the corporate network." "WARNING"
                    $allTestsPassed = $false
                }
            }

            # 3. The expected IP resolution(s) should be private/internal addresses.
            foreach ($expectedIP in $expectedIPs) {
                if (-not (Test-GSAIsPrivateIPv4 -IPAddress $expectedIP)) {
                    Write-Log "Private Network '$networkName' expects the probe to resolve to a public/non-RFC1918 address ($expectedIP)." "WARNING"
                    Write-Log "Recommended action: Verify '$networkName' is intentionally using a public IP as its corporate-network indicator; this is unusual for Intelligent Local Access." "WARNING"
                }
            }
        }
    }

    if ($allTestsPassed) {
        Write-Log "Test passed: No Intelligent Local Access misconfigurations detected across $($privateNetworks.Count) Private Network(s)." "SUCCESS"
    }

    if ($PassThru) { return $allTestsPassed }
}

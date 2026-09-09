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
.PARAMETER FQDN
    Manually check a single candidate probe FQDN instead of retrieving Private Network definitions from
    Microsoft Graph - no Graph call or sign-in is made. Useful to validate a candidate FQDN before
    configuring it as an Intelligent Local Access Private Network in Entra.
.PARAMETER DnsServerAddress
    One or more DNS server IPv4 addresses to also validate as private/internal (RFC1918). Only used
    together with -FQDN.
.PARAMETER ExpectedIPAddress
    One or more expected resolved IPv4 addresses to also validate as private/internal (RFC1918). Only
    used together with -FQDN.
.PARAMETER PublicDnsServer
    The DNS-over-HTTPS (DoH) JSON API endpoint used to check whether a probe FQDN is publicly
    resolvable (default: https://dns.google/resolve).
.PARAMETER PassThru
    Return the $true/$false test result. By default nothing is returned - only logged.
.EXAMPLE
    Test-GSAIntelligentLocalAccessConfiguration
.EXAMPLE
    Test-GSAIntelligentLocalAccessConfiguration -AccessToken $token -PassThru
.EXAMPLE
    Test-GSAIntelligentLocalAccessConfiguration -FQDN unifi.home.contoso.com -DnsServerAddress 192.168.1.1 -ExpectedIPAddress 192.168.1.1
#>
    [CmdletBinding(DefaultParameterSetName = 'Graph')]
    param (
        [Parameter(ParameterSetName = 'Graph')]
        [string]$AccessToken,
        [Parameter(ParameterSetName = 'Manual', Mandatory)]
        [string]$FQDN,
        [Parameter(ParameterSetName = 'Manual')]
        [string[]]$DnsServerAddress,
        [Parameter(ParameterSetName = 'Manual')]
        [string[]]$ExpectedIPAddress,
        [string]$PublicDnsServer = "https://dns.google/resolve",
        [switch]$PassThru,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    if ($PSCmdlet.ParameterSetName -eq 'Manual') {
        Write-Log "Manually checking probe FQDN '$FQDN' for Intelligent Local Access misconfigurations..." "INFO"
        $passed = Test-GSAILAProbeIdentification -ContextLabel "Manual check for '$FQDN':" -FQDN $FQDN -ServerAddresses $DnsServerAddress -ExpectedIPs $ExpectedIPAddress -PublicDnsServer $PublicDnsServer
        if ($passed) {
            Write-Log "Test passed: No Intelligent Local Access misconfigurations detected for '$FQDN'." "SUCCESS"
        }
        if ($PassThru) { return $passed }
        return
    }

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

            $identificationPassed = Test-GSAILAProbeIdentification -ContextLabel "Private Network '$networkName'" -FQDN $fqdn -ServerAddresses $serverAddresses -ExpectedIPs $expectedIPs -PublicDnsServer $PublicDnsServer
            if (-not $identificationPassed) {
                $allTestsPassed = $false
            }
        }
    }

    if ($allTestsPassed) {
        Write-Log "Test passed: No Intelligent Local Access misconfigurations detected across $($privateNetworks.Count) Private Network(s)." "SUCCESS"
    }

    if ($PassThru) { return $allTestsPassed }
}

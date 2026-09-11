#
# Function: Test-GSAILAProbeIdentification
# Validates a single Intelligent Local Access (ILA) DNS-based network identification: checks that the
# probe FQDN isn't publicly resolvable (via DNS-over-HTTPS) and that its DNS server/expected IP
# addresses are private (RFC1918). Shared by Test-GSAIntelligentLocalAccessConfiguration for both
# Graph-retrieved Private Networks and ad-hoc manual checks.
# Example: Test-GSAILAProbeIdentification -ContextLabel "Private Network 'Home sweet home'" -FQDN unifi.home.contoso.com -PublicDnsServer https://dns.google/resolve
#
function Test-GSAILAProbeIdentification
{
	param (
		[string]$ContextLabel,
		[Parameter(Mandatory)]
		[string]$FQDN,
		[string[]]$ServerAddresses,
		[string[]]$ExpectedIPs,
		[Parameter(Mandatory)]
		[string]$PublicDnsServer
	)

	$passed = $true

	# 1. The probe FQDN must NOT be resolvable via a public DNS resolver - if it is, corporate-network
	#    detection can be satisfied from anywhere, causing GSA to falsely bypass traffic locally.
	#    Uses DNS-over-HTTPS rather than a classic port-53 query, since the latter can be silently
	#    intercepted/answered by the local GSA client or a router's own local DNS records.
	$publiclyResolvable = $false
	$publicIPs = @()
	try
    {
		$dohUri = "$PublicDnsServer`?name=$([uri]::EscapeDataString($FQDN))&type=A"
		$dohResponse = Invoke-RestMethod -Uri $dohUri -Headers @{ Accept = 'application/dns-json' } -ErrorAction Stop
		if ($dohResponse.Status -eq 0)
        {
			# Status 0 (NOERROR) alone doesn't guarantee an A record exists - a NODATA response
			# (e.g. only an Authority/SOA section, no Answer) means the zone exists but this
			# name doesn't resolve publicly, so only a non-empty Answer counts as resolvable.
			$publicIPs = @($dohResponse.Answer | Where-Object { $_.type -eq 1 } | Select-Object -ExpandProperty data -ErrorAction SilentlyContinue)
			$publiclyResolvable = $publicIPs.Count -gt 0
		}
		elseif ($dohResponse.Status -ne 3) {
			# Status 3 (NXDOMAIN) simply means "not resolvable" - anything else is inconclusive
			Write-Log "Could not determine public resolvability of '$FQDN' via DNS-over-HTTPS ($PublicDnsServer): DNS status code $($dohResponse.Status)." "WARNING"
		}
	}
	catch
    {
		Write-Log "Could not determine public resolvability of '$FQDN' via DNS-over-HTTPS ($PublicDnsServer): $($_.Exception.Message)" "WARNING"
	}

	if ($publiclyResolvable)
    {
		# A GSA-only device could still return its own synthetic 6.6.x.x address if the DoH provider
		# itself happened to be covered by a Private Access rule - vanishingly unlikely, but checked
		# anyway as defense-in-depth so this never produces a false failure.
		$syntheticIPs = @($publicIPs | Where-Object { $_ -like '6.6.*' })
		if ($syntheticIPs.Count -gt 0 -and $syntheticIPs.Count -eq $publicIPs.Count)
        {
			Write-Log "$ContextLabel probe FQDN '$FQDN' resolved to a GSA synthetic address ($($syntheticIPs -join ', ')) - the local GSA client is intercepting this query, so public resolvability can't be verified from this device." "WARNING"
			Write-Log "Recommended action: Re-run this check from a device without the GSA client active for '$FQDN' (e.g. temporarily disable Private Access, or use a machine that doesn't have it installed) to get a trustworthy result." "WARNING"
		}
		else
        {
			$ipInfo = if ($publicIPs.Count -gt 0) { " (resolves to $($publicIPs -join ', '))" } else { "" }
			Write-Log "$ContextLabel probe FQDN '$FQDN' is PUBLICLY resolvable via DNS-over-HTTPS$ipInfo." "ERROR"
			Write-Log "Recommended action: Use an FQDN that only resolves on your internal/corporate DNS servers (no public DNS record). A publicly resolvable probe FQDN defeats corporate-network detection and can cause GSA to incorrectly bypass Private Access traffic locally for users who are NOT on the corporate network (a confirmed real-world root cause of client connectivity failures on hotel/home networks)." "WARNING"
			$passed = $false
		}
	}
	else
    {
		Write-Log "$ContextLabel probe FQDN '$FQDN' is not publicly resolvable - OK." "SUCCESS"
	}

	# 2. The DNS server(s) used for the probe should be private/internal addresses only.
	foreach ($serverAddress in @($ServerAddresses | Where-Object { $_ }))
    {
		if (-not (Test-GSAIsPrivateIPv4 -IPAddress $serverAddress))
        {
			Write-Log "$ContextLabel uses a public/non-RFC1918 DNS server address ($serverAddress) for corporate-network detection." "ERROR"
			Write-Log "Recommended action: Configure an internal DNS server address that is only reachable from inside the corporate network." "WARNING"
			$passed = $false
		}
	}

	# 3. The expected IP resolution(s) should be private/internal addresses.
	foreach ($expectedIP in @($ExpectedIPs | Where-Object { $_ }))
    {
		if (-not (Test-GSAIsPrivateIPv4 -IPAddress $expectedIP))
        {
			Write-Log "$ContextLabel expects the probe to resolve to a public/non-RFC1918 address ($expectedIP)." "WARNING"
			Write-Log "Recommended action: Verify this is intentionally using a public IP as its corporate-network indicator; this is unusual for Intelligent Local Access." "WARNING"
		}
	}

	return $passed
}

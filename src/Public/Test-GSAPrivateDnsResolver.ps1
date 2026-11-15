#
# Function: Test-GSAPrivateDnsResolver
# Queries the GSA-internal DNS resolver at 6.6.255.254 over TCP.
# This address is only reachable through the GSA Private Access tunnel, so a successful
# response (even NXDOMAIN) proves the tunnel is up and Private Access DNS forwarding is working.
# Private DNS is a Quick Access feature (configured on the Quick Access app's Private DNS tab),
# so this resolver is only ever provisioned - via a local NRPT rule - on devices where Quick
# Access + Private DNS is actually enabled. Tenants that only use Enterprise Applications
# (per-app access) never create that NRPT rule, so this check first confirms a Private DNS NRPT
# rule exists before probing the resolver; otherwise it reports "not applicable" instead of a
# false failure. See https://learn.microsoft.com/entra/global-secure-access/concept-private-name-resolution
# and https://learn.microsoft.com/entra/global-secure-access/troubleshoot-app-access#how-does-dns-work-with-global-secure-access
#
function Test-GSAPrivateDnsResolver
{
	<#
.SYNOPSIS
	Verifies the GSA-internal DNS resolver (6.6.255.254) is reachable through the Private Access tunnel.
.DESCRIPTION
	The address 6.6.255.254 is the GSA synthetic DNS resolver. Per Microsoft Learn, Private DNS is
	a feature of Quick Access: it's only enabled from the Quick Access app's Private DNS tab, and
	only then does the GSA client add a local Name Resolution Policy Table (NRPT) rule directing
	matching queries to 6.6.255.254. Tenants that use only Enterprise Applications (per-app access)
	without Quick Access/Private DNS never create this NRPT rule, so 6.6.255.254 is never reachable
	for them - that isn't a tunnel problem.
	This check first looks for a local NRPT rule whose name servers include 6.6.255.254 (or whose
	namespace targets the GSA synthetic suffix). If none is found, Private DNS isn't configured on
	this device and the check reports success as not applicable, instead of a false failure. When
	such an NRPT rule is found, a response from the resolver (including NXDOMAIN) confirms the
	tunnel is up and DNS forwarding is functioning; a timeout or connection failure then means the
	tunnel is not active or Private Access is not enabled.
.PARAMETER PassThru
	Return the $true/$false test result. By default nothing is returned - only logged.
.OUTPUTS
	System.Boolean when -PassThru is specified. No output is returned by default.
.LINK
	https://learn.microsoft.com/entra/global-secure-access/concept-private-name-resolution
.LINK
	https://learn.microsoft.com/entra/global-secure-access/troubleshoot-app-access#how-does-dns-work-with-global-secure-access
#>
	[CmdletBinding()]
	param (
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	Write-Log "Checking whether Private DNS (a Quick Access feature) is configured on this device..." "INFO"

	# Private DNS only exists on a device when Quick Access + Private DNS is enabled for the
	# tenant; that's the only configuration path that provisions an NRPT rule pointing at the
	# synthetic resolver. Enterprise Applications (per-app access) alone never create it.
	$privateDnsConfigured = $true
	try
    {
		$nrptRules = @(Get-DnsClientNrptRule -ErrorAction Stop)
		$privateDnsConfigured = [bool]($nrptRules | Where-Object {
			($_.NameServers -contains '6.6.255.254') -or
			($_.Namespace -match '(?i)globalsecureaccess\.local$')
		})
	}
	catch
    {
		Write-Log "Could not read local NRPT rules: $($_.Exception.Message). Proceeding to probe the resolver directly." "WARNING"
	}

	if (-not $privateDnsConfigured)
    {
		Write-Log "No local NRPT rule targets the GSA Private DNS resolver (6.6.255.254). Private DNS is a Quick Access feature and is not configured on this device - skipping as not applicable (this is expected for tenants using only Enterprise Applications)." "SUCCESS"
		if ($PassThru)
		{ return $true }
		return
	}

	Write-Log "Querying GSA Private DNS resolver (6.6.255.254) via TCP..." "INFO"

	try
    {
		# Any response (including NXDOMAIN) confirms the resolver is reachable through the tunnel
		[void](Resolve-DnsName -Name "connectivity.check.gsa.internal" -Server 6.6.255.254 -TcpOnly -ErrorAction Stop)
		Write-Log "GSA Private DNS resolver (6.6.255.254) responded - Private Access tunnel is active." "SUCCESS"
		if ($PassThru)
		{ return $true }
		return
	}
	catch
    {
		$errorMsg = $_.Exception.Message
		# DNS error codes like NXDOMAIN / SERVFAIL still mean the server responded
		if ($errorMsg -match "DNS name does not exist|NXDOMAIN|server failure|SERVFAIL|query refused")
        {
			Write-Log "GSA Private DNS resolver (6.6.255.254) responded - tunnel is active." "SUCCESS"
			if ($PassThru)
			{ return $true }
			return
		}
		else
        {
			# Timeout or connection refused means the tunnel is not up
			Write-Log "GSA Private DNS resolver (6.6.255.254) is unreachable: $errorMsg. Ensure Private Access is enabled and the GSA tunnel services are running." "ERROR"
			if ($PassThru)
			{ return $false }
			return
		}
	}
}

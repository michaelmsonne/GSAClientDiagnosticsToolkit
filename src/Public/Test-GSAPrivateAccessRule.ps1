#
# Function: Test-GSAPrivateAccessRule
# Public function for the GSA client diagnostics toolkit.
#
function Test-GSAPrivateAccessRule
{
	<#
.SYNOPSIS
	Checks whether the locally cached GSA forwarding profile permits a target/port/protocol via Private Access.
.DESCRIPTION
	Reads the ForwardingProfile registry value and evaluates its policy.rules against the supplied
	FQDN or IPv4 address, port, and protocol - mirroring the client-side rule matching the GSA client
	performs itself. This validates the local client configuration only; it does not call Microsoft Graph
	or require sign-in, unlike checking the application/profile assignment in the Entra portal.
.PARAMETER FQDNorIP
	The target FQDN or IPv4 address to test.
.PARAMETER Port
	The target TCP/UDP port number.
.PARAMETER Protocol
	The protocol to test (TCP or UDP).
.PARAMETER RegistryValueName
	Registry value name containing the GSA JSON policy (default: ForwardingProfile).
.PARAMETER PassThru
	Return the $true/$false test result. By default nothing is returned - only logged - so calling
	this function interactively doesn't echo a stray True/False after the log output.
.EXAMPLE
	Test-GSAPrivateAccessRule -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP
.EXAMPLE
	if (Test-GSAPrivateAccessRule -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP -PassThru)
    { ... }
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$FQDNorIP,
		[Parameter(Mandatory)]
		[int]$Port,
		[Parameter(Mandatory)]
		[ValidateSet("TCP", "UDP")]
		[string]$Protocol,
		[string]$RegistryValueName = "ForwardingProfile",
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	$inputType = Test-IPorFQDN -FQDNorIP $FQDNorIP
	if (-not $inputType)
    {
		Write-Log "'$FQDNorIP' is not a valid IPv4 address or FQDN." "ERROR"
		if ($PassThru)
        { return $false }
		return
	}

	Write-Log "Checking Private Access rules in the local forwarding profile for ${FQDNorIP}:${Port}/${Protocol}..." "INFO"

	# Load the GSA forwarding profile from the registry and parse it as JSON.
	$jsonContent = Get-JsonFromRegistry -ValueName $RegistryValueName
	if (-not $jsonContent)
    {
		Write-Log "Failed to load GSA client configuration from the registry." "ERROR"
		if ($PassThru)
        { return $false }
		return
	}

	# Extract the Private Access rules from the parsed JSON content.
	$rules = @($jsonContent.policy.rules)
	if ($rules.Count -eq 0 -or -not $rules[0])
    {
		Write-Log "No Private Access rules found in the forwarding profile. Ensure Private Access is enabled and at least one application is configured in Entra portal." "ERROR"
		if ($PassThru)
        { return $false }
		return
	}

	# Find the matching Private Access rule for the given FQDN/IP, port, and protocol.
	$match = Get-GSAPrivateAccessRuleMatch -Rules $rules -FQDNorIP $FQDNorIP -InputType $inputType -Port $Port -Protocol $Protocol

	if (-not $match.AddressMatched)
    {
		Write-Log "'$FQDNorIP' is not covered by any Private Access rule in the local forwarding profile." "ERROR"
		Write-Log "Recommended action: Ensure '$FQDNorIP' is configured as a destination in a Private Access application (Entra > Global Secure Access > Applications) and that the profile has been re-downloaded (delete the ForwardingProfileTimestamp registry value and restart GlobalSecureAccessForwardingProfileService)." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	Write-Log "'$FQDNorIP' is covered by rule '$($match.RuleId)' (App ID: $($match.AppId))." "SUCCESS"

	if (-not $match.PortMatched)
    {
		Write-Log "Port $Port is NOT configured for the matching Private Access application (App ID: $($match.AppId))." "ERROR"
		Write-Log "Recommended action: Add port $Port to the application segment for App ID: $($match.AppId)." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	Write-Log "Port $Port is configured for the matching Private Access application." "SUCCESS"

	if (-not $match.ProtocolMatched)
    {
		Write-Log "Protocol $Protocol is NOT configured for port $Port on the matching Private Access application (App ID: $($match.AppId))." "ERROR"
		Write-Log "Recommended action: Add the $Protocol protocol to the matching application segment for App ID: $($match.AppId)." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}

	Write-Log "Test passed: '$FQDNorIP' on port $Port/$Protocol is allowed by the local Private Access forwarding profile (Rule ID: $($match.RuleId), App ID: $($match.AppId))." "SUCCESS"
	if ($PassThru)
    { return $true }
}

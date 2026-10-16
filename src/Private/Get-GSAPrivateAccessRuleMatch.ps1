#
# Function: Get-GSAPrivateAccessRuleMatch
# Evaluates a forwarding profile's Private Access rules against a target address/port/protocol,
# mirroring the client-side rule matching the GSA client performs itself.
# Example: Get-GSAPrivateAccessRuleMatch -Rules $json.policy.rules -FQDNorIP 'fileserver.contoso.com' -InputType 'FQDN' -Port 445 -Protocol 'TCP'
#
function Get-GSAPrivateAccessRuleMatch
{
	param (
		[object[]]$Rules,
		[string]$FQDNorIP,
		[ValidateSet("IP", "FQDN")]
		[string]$InputType,
		[int]$Port,
		[string]$Protocol
	)

	$result = [PSCustomObject]@{
		AddressMatched  = $false
		PortMatched     = $false
		ProtocolMatched = $false
		RuleId          = $null
		AppId           = $null
	}

	# Iterate through the Private Access rules to check for address, port, and protocol matches.
	foreach ($rule in $Rules)
    {
		$addressMatch = $false

		if ($InputType -eq 'IP')
        {
			foreach ($ipRange in @($rule.matchingCriteria.address.ips))
            {
				if ($ipRange -and (Test-GSAIPInRange -Start $ipRange.start -End $ipRange.end -IPAddress $FQDNorIP))
                {
					$addressMatch = $true
					break
				}
			}
		}
		else
        {
			foreach ($fqdnPattern in @($rule.matchingCriteria.address.fqdns))
            {
				if ($fqdnPattern -and $FQDNorIP -match "^$fqdnPattern`$")
                {
					$addressMatch = $true
					break
				}
			}
		}

		if (-not $addressMatch)
        { continue }

		$result.AddressMatched = $true
		$audienceScope = $rule.appAuthorizationTokenContext.audienceScope
		$result.RuleId = $rule.id
		$result.AppId = if ($audienceScope -match 'api://([^/]+)') { $Matches[1] } else { $null }

		if (-not (Test-GSAPortInRange -Ports $rule.matchingCriteria.ports -Port $Port))
        { continue }
		$result.PortMatched = $true

		if ($rule.matchingCriteria.protocol -eq $Protocol -or $rule.matchingCriteria.protocol -eq 'All')
        {
			$result.ProtocolMatched = $true
			break
		}
	}

	return $result
}

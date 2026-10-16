#
# Function: Test-IPorFQDN
# Determines whether a string is a valid IPv4 address or a valid FQDN.
# Example: Test-IPorFQDN -FQDNorIP 'fileserver.contoso.com'   # returns 'FQDN'
#
function Test-IPorFQDN
{
	param (
		[string]$FQDNorIP
	)

	# Define regular expressions for matching IPv4 addresses and FQDNs.
	$ipRegex = '^(([0-9]{1,3}\.){3}[0-9]{1,3})$'
	$fqdnRegex = '^([a-zA-Z0-9]+(-[a-zA-Z0-9]+)*\.)+[a-zA-Z]{2,}$'

	# Check if the input string matches the IPv4 address pattern.
	if ($FQDNorIP -match $ipRegex)
    {
		foreach ($octet in ($FQDNorIP -split '\.'))
        {
			if ([int]$octet -lt 0 -or [int]$octet -gt 255)
            {
				return $null
			}
		}
		return 'IP'
	}

	# Check if the input string matches the FQDN pattern.
	if ($FQDNorIP -match $fqdnRegex)
    {
		return 'FQDN'
	}

	return $null
}

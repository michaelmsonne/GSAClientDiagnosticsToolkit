#
# Function: ConvertTo-GSAIPv4Number
# Converts an IPv4 boundary from a forwarding profile rule to its numeric (host-order) value.
# Older profiles store the bound as a number (e.g. 3232235777); newer ones as an object with the
# address family and dotted value (e.g. @{f=4; v='192.168.1.1'}). Returns $null for IPv6 or
# anything that can't be parsed as an IPv4 address.
# Example: ConvertTo-GSAIPv4Number -Value ([PSCustomObject]@{ f = 4; v = '192.168.1.1' })   # returns 3232235777
#
function ConvertTo-GSAIPv4Number
{
	param (
		[object]$Value
	)

	if ($null -eq $Value)
    { return $null }

	if ($Value -is [ValueType] -and $Value -isnot [bool])
    {
		try
        { return [uint64]$Value }
		catch
        { return $null }
	}

	if ($Value -is [string])
    { $address = $Value }
	elseif ($Value.PSObject.Properties.Match('v').Count -gt 0)
    {
		if ($Value.PSObject.Properties.Match('f').Count -gt 0 -and [int]$Value.f -ne 4)
        { return $null }
		$address = [string]$Value.v
	}
	else
    { return $null }

	$parsed = $null
	if (-not [System.Net.IPAddress]::TryParse($address, [ref]$parsed) -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork)
    { return $null }

	$bytes = $parsed.GetAddressBytes()
	[Array]::Reverse($bytes)
	return [uint64][BitConverter]::ToUInt32($bytes, 0)
}

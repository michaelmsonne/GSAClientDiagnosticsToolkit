#
# Function: Test-GSAIPInRange
# Checks whether an IPv4 address falls within a decimal [Start, End] address range.
# Example: Test-GSAIPInRange -Start 167772160 -End 167772415 -IPAddress '10.0.0.42'   # returns $true
#
function Test-GSAIPInRange
{
	param (
		[uint32]$Start,
		[uint32]$End,
		[string]$IPAddress
	)

	# Convert the IP address to its numeric representation for comparison.
	$bytes = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
	[Array]::Reverse($bytes)
	$value = [BitConverter]::ToUInt32($bytes, 0)

	return ($value -ge $Start -and $value -le $End)
}

#
# Function: Test-GSAPortInRange
# Checks whether a port number falls within any of the given [start, end] port ranges.
# Example: Test-GSAPortInRange -Ports @([PSCustomObject]@{ start = 400; end = 500 }) -Port 445   # returns $true
#
function Test-GSAPortInRange
{
	param (
		[object[]]$Ports,
		[int]$Port
	)

	foreach ($range in $Ports)
	{
		if ($range -and $Port -ge $range.start -and $Port -le $range.end)
		{
			return $true
		}
	}
	return $false
}

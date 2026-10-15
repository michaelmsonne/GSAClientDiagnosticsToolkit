#
# Function: ConvertTo-GSAPortRange
# Converts Graph application segment port strings ("start-end") into {start,end} objects.
# Example: ConvertTo-GSAPortRange -Ranges @("443-443","1000-2000")
#
function ConvertTo-GSAPortRange {
	param (
		[string[]]$Ranges
	)

	$result = @()
	foreach ($range in @($Ranges)) {
		$bounds = $range -split '-'
		if ($bounds.Count -eq 2) {
			$result += [PSCustomObject]@{ start = [int]$bounds[0]; end = [int]$bounds[1] }
		}
	}
	return $result
}

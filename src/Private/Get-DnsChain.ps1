# 
# Function: Get-DnsChain
# Recursively retrieves the CNAME chain for a given FQDN.
# 
function Get-DnsChain
{
	param (
		[string]$fqdn,
		[int]$depth = 0,
		[hashtable]$visited = @{}
	)

	# Limit recursion to avoid infinite loops (max 10 levels)
	if ($depth -ge 10)
    {
		Write-Log "Recursion limit reached for $fqdn" "WARNING"
		return @()
	}

	# Avoid processing the same FQDN more than once.
	if ($visited.ContainsKey($fqdn))
    { return @() }
	$visited[$fqdn] = $true

	$chain = @()

	try
    {
		$records = Resolve-DnsName -Name $fqdn -ErrorAction Stop
	}
	catch
    {
		Write-Log "Failed to resolve $fqdn when chasing CNAMEs: $($_.Exception.Message)" "ERROR"
		return @()
	}

	# Look for CNAME records in the result.
	$cnameRecords = $records | Where-Object { $_.QueryType -eq "CNAME" }
	foreach ($record in $cnameRecords)
    {
		$target = $record.NameHost
		# Skip self-referential CNAMEs (injected by GSA synthetic DNS) and already-visited targets
		if ([string]::IsNullOrEmpty($target) -or $target -eq $fqdn -or $visited.ContainsKey($target))
        { continue }
		# Append the CNAME target.
		$chain += $target
		# Recursively check for additional CNAMEs.
		$childChain = Get-DnsChain -fqdn $target -depth ($depth + 1) -visited $visited
		if ($childChain)
        { $chain += $childChain }
	}
	return $chain
}

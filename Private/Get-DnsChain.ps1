function Get-DnsChain {
    param (
        [string]$fqdn,
        [int]$depth = 0,
        [hashtable]$visited = @{}
    )

    if ($depth -ge 10) {
        Write-Log "Recursion limit reached for $fqdn" "WARNING"
        return @()
    }

    if ($visited.ContainsKey($fqdn)) { return @() }
    $visited[$fqdn] = $true

    $chain = @()

    try {
        $records = Resolve-DnsName -Name $fqdn -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to resolve $fqdn when chasing CNAMEs: $_" "ERROR"
        return @()
    }

    $cnameRecords = $records | Where-Object { $_.QueryType -eq "CNAME" }
    foreach ($record in $cnameRecords) {
        $chain += $record.Name
        $childChain = Get-DnsChain -fqdn $record.Name -depth ($depth + 1) -visited $visited
        if ($childChain) { $chain += $childChain }
    }
    return $chain
}

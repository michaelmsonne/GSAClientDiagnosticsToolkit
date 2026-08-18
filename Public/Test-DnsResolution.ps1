function Test-DnsResolution {
<#
.SYNOPSIS
    Tests DNS resolution for a list of FQDNs and logs CNAME chains.
.PARAMETER fqdnList
    List of FQDNs to resolve.
#>
    param (
        [string[]]$fqdnList
    )

    $allTestsPassed = $true

    foreach ($fqdn in $fqdnList) {
        Write-Log "Checking DNS resolution for: $fqdn" "INFO"

        try {
            $records = Resolve-DnsName -Name $fqdn -NoHostsFile -ErrorAction Stop

            $ipAddresses = $records | Where-Object { $_.QueryType -eq "A" -or $_.QueryType -eq "AAAA" } |
                           Select-Object -ExpandProperty IPAddress -Unique

            if ($ipAddresses) {
                Write-Log "DNS resolution for $fqdn returned IP addresses: $($ipAddresses -join ', ')" "SUCCESS"
            } else {
                Write-Log "DNS resolution for $fqdn did not return any A/AAAA records." "WARNING"
            }

            $cnameChain = Get-DnsChain -fqdn $fqdn
            if ($cnameChain.Count -gt 0) {
                Write-Log "CNAME chain for $fqdn (Depth: $($cnameChain.Count)): $fqdn -> $($cnameChain -join ' -> ')" "INFO"
            } else {
                Write-Log "No CNAME records found for $fqdn." "INFO"
            }
        }
        catch {
            Write-Log "DNS resolution for $fqdn failed: $_" "ERROR"
            $allTestsPassed = $false
        }
    }
    return $allTestsPassed
}

#
# Function: Test-DnsResolution
# Public function for the GSA client diagnostics toolkit.
#
function Test-DnsResolution {
    <#
.SYNOPSIS
    Tests DNS resolution for a list of FQDNs and logs CNAME chains.
.PARAMETER fqdnList
    List of FQDNs to resolve.
#>
    [CmdletBinding()]
    param (
        [string[]]$fqdnList,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    $allTestsPassed = $true

    foreach ($fqdn in $fqdnList) {
        Write-Log "Checking DNS resolution for: $fqdn" "INFO"

        try {
            # Resolve DNS for all record types
            $records = Resolve-DnsName -Name $fqdn -NoHostsFile -ErrorAction Stop

            # Extract A and AAAA records (IP addresses)
            $ipAddresses = $records | Where-Object { $_.QueryType -eq "A" -or $_.QueryType -eq "AAAA" } |
            Select-Object -ExpandProperty IPAddress -Unique

            if ($ipAddresses) {
                Write-Log "DNS resolution for $fqdn returned IP addresses: $($ipAddresses -join ', ')" "SUCCESS"
            }
            else {
                Write-Log "DNS resolution for $fqdn did not return any A/AAAA records." "WARNING"
            }

            # Retrieve the CNAME chain (if any)
            $cnameChain = Get-DnsChain -fqdn $fqdn
            if ($cnameChain.Count -gt 0) {
                Write-Log "CNAME chain for $fqdn ($($cnameChain.Count) hop(s)):" "INFO"
                Write-Log "  $fqdn" "INFO"
                foreach ($hop in $cnameChain) {
                    Write-Log "  -> $hop" "INFO"
                }
            }
            else {
                Write-Log "No CNAME records found for $fqdn." "INFO"
            }
        }
        catch {
            Write-Log "DNS resolution for $fqdn failed: $($_.Exception.Message)" "ERROR"
            $allTestsPassed = $false
        }
    }
    return $allTestsPassed
}

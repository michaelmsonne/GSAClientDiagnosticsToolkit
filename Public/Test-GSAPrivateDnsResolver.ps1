#
# Function: Test-GSAPrivateDnsResolver
# Queries the GSA-internal DNS resolver at 6.6.255.254 over TCP.
# This address is only reachable through the GSA Private Access tunnel, so a successful
# response (even NXDOMAIN) proves the tunnel is up and Private Access DNS forwarding is working.
#
function Test-GSAPrivateDnsResolver {
<#
.SYNOPSIS
    Verifies the GSA-internal DNS resolver (6.6.255.254) is reachable through the Private Access tunnel.
.DESCRIPTION
    The address 6.6.255.254 is the GSA synthetic DNS resolver. It is only reachable when the
    GSA Private Access tunnel is active. A response (including NXDOMAIN) confirms the tunnel
    is up and DNS forwarding is functioning. A timeout or connection failure means the tunnel
    is not active or Private Access is not enabled.
#>
    Write-Log "Querying GSA Private DNS resolver (6.6.255.254) via TCP..." "INFO"

    try {
        # Any response (including NXDOMAIN) confirms the resolver is reachable through the tunnel
        [void](Resolve-DnsName -Name "connectivity.check.gsa.internal" -Server 6.6.255.254 -TcpOnly -ErrorAction Stop)
        Write-Log "GSA Private DNS resolver (6.6.255.254) responded - Private Access tunnel is active." "SUCCESS"
        return $true
    } catch {
        $errorMsg = $_.Exception.Message
        # DNS error codes like NXDOMAIN / SERVFAIL still mean the server responded
        if ($errorMsg -match "DNS name does not exist|NXDOMAIN|server failure|SERVFAIL|query refused") {
            Write-Log "GSA Private DNS resolver (6.6.255.254) responded (DNS error expected for test name) - tunnel is active." "SUCCESS"
            return $true
        } else {
            # Timeout or connection refused means the tunnel is not up
            Write-Log "GSA Private DNS resolver (6.6.255.254) is unreachable: $errorMsg. Ensure Private Access is enabled and the GSA tunnel services are running." "ERROR"
            return $false
        }
    }
}

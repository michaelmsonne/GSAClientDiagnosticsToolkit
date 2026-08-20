function Test-GSAPrivateAccessTunnel {
    <#
.SYNOPSIS
    Tests that a Private Access target actually tunnels through the GSA client.
.DESCRIPTION
    Opens a TCP connection to the given FQDN or IPv4 address/port. For FQDN targets, verifies the
    connection was routed to a synthetic 6.6.x.x address (proving GSA intercepted and tunneled the
    traffic) and resolves the internal address via the GSA Private DNS resolver (6.6.255.254).
    UDP targets cannot be tunnel-tested this way and are reported as a warning only.
.PARAMETER FQDNorIP
    The target FQDN or IPv4 address to test.
.PARAMETER Port
    The target port number.
.PARAMETER Protocol
    The protocol to test (TCP or UDP).
.PARAMETER PassThru
    Return the $true/$false test result. By default nothing is returned - only logged - so calling
    this function interactively doesn't echo a stray True/False after the log output.
.EXAMPLE
    Test-GSAPrivateAccessTunnel -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP
.EXAMPLE
    if (Test-GSAPrivateAccessTunnel -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP -PassThru) { ... }
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FQDNorIP,
        [Parameter(Mandatory)]
        [int]$Port,
        [Parameter(Mandatory)]
        [ValidateSet("TCP", "UDP")]
        [string]$Protocol,
        [switch]$PassThru,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    $inputType = Test-IPorFQDN -FQDNorIP $FQDNorIP
    if (-not $inputType) {
        Write-Log "'$FQDNorIP' is not a valid IPv4 address or FQDN." "ERROR"
        if ($PassThru) { return $false }
        return
    }

    if ($Protocol -eq 'UDP') {
        Write-Log "UDP tunnel connectivity cannot be verified with a TCP-based probe." "WARNING"
        if ($PassThru) { return [PSCustomObject]@{ Passed = $true; Warnings = 1 } }
        return
    }

    Write-Log "Checking Private Access tunnel connectivity to ${FQDNorIP}:${Port}..." "INFO"

    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new($FQDNorIP, $Port)
    }
    catch {
        Write-Log "Failed to establish a tunnel connection to ${FQDNorIP}:${Port} : $_" "ERROR"
        Write-Log "Recommended action: Ensure the Private Access application segment, port, and protocol are correctly configured and that the GSA client tunnel is active." "WARNING"
        if ($PassThru) { return $false }
        return
    }

    try {
        $syntheticAddress = $tcpClient.Client.RemoteEndPoint.Address.ToString()
    }
    finally {
        $tcpClient.Close()
    }

    Write-Log "Tunnel connection established. Synthetic address: $syntheticAddress" "SUCCESS"

    if ($inputType -eq 'FQDN') {
        if ($syntheticAddress -notlike '6.6.*') {
            Write-Log "Connection to '$FQDNorIP' did NOT resolve to a synthetic GSA address (6.6.x.x) - traffic may not be tunneled through GSA." "ERROR"
            Write-Log "Recommended action: Ensure the GSA client is active and this FQDN is not being resolved/routed outside the tunnel." "WARNING"
            if ($PassThru) { return $false }
            return
        }

        try {
            $dnsResult = Resolve-DnsName -Name $FQDNorIP -Server 6.6.255.254 -TcpOnly -ErrorAction Stop
            Write-Log "Internal address for '$FQDNorIP' resolved via GSA Private DNS: $($dnsResult.IPAddress -join ', ')" "SUCCESS"
        }
        catch {
            Write-Log "Could not resolve the internal DNS name for '$FQDNorIP' via the GSA Private DNS resolver: $_" "ERROR"
            Write-Log "Recommended action: Ensure Private DNS is configured and the Private Network Connector can resolve this name." "WARNING"
            if ($PassThru) { return $false }
            return
        }
    }

    Write-Log "Test passed: tunnel to '$FQDNorIP' on port $Port established successfully via GSA (synthetic address: $syntheticAddress)." "SUCCESS"
    if ($PassThru) { return $true }
}

function Test-InternetConnectivity {
    <#
.SYNOPSIS
    Tests basic internet connectivity: active routes, website reachability, and DNS server reachability.
.PARAMETER Websites
    Websites to test for reachability.
.PARAMETER DnsServers
    DNS servers to test for reachability over UDP port 53.
.PARAMETER TimeoutMs
    UDP receive timeout in milliseconds.
#>
    [CmdletBinding()]
    param (
        [string[]]$Websites = @("www.google.com", "www.microsoft.com"),
        [string[]]$DnsServers = @("1.1.1.1", "8.8.8.8", "9.9.9.9"),
        [int]$TimeoutMs = 5000,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    # Set default state for tests
    $allTestsPassed = $true

    # Check for active network interfaces with default routes
    $defaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne "::" }
    if ($defaultRoutes) {
        Write-Log "Active network interfaces with default routes detected." "INFO"
    }
    else {
        Write-Log "No active network interfaces with default routes found." "ERROR"
        $allTestsPassed = $false
    }

    # Test reachability of specified websites
    foreach ($site in $Websites) {
        $testResult = Test-NetConnection -ComputerName $site -InformationLevel Quiet
        if ($testResult) {
            Write-Log "Website $site is reachable." "INFO"
        }
        else {
            Write-Log "Website $site is not reachable." "ERROR"
            $allTestsPassed = $false
        }
    }

    # Test reachability of specified DNS servers over TCP and UDP
    foreach ($dns in $DnsServers) {
        # UDP Check
        $udpTestResult = Test-UDPPort -IPAddress $dns -Timeout $TimeoutMs
        if ($udpTestResult) {
            Write-Log "DNS server $dns is reachable on UDP port 53." "INFO"
        }
        else {
            Write-Log "DNS server $dns is not reachable on UDP port 53." "ERROR"
            $allTestsPassed = $false
        }
    }

    return $allTestsPassed
}

function Invoke-GSAClientConnectivityCheck {
<#
.SYNOPSIS
    Runs all GSA Client connectivity, proxy, health probe, and mTLS checks.

.DESCRIPTION
    Executes the full diagnostic suite:
        1. Active network interfaces with default routes
        2. Reachability of specified websites
        3. Reachability of specified DNS servers
        4. Read the GSA JSON from the registry
        5. Extract Edge Addresses from JSON
        6. Test DNS resolution for each FQDN
        7. Test TLS connectivity to each FQDN
        8. Test mTLS connectivity to each FQDN
        9. Test gRPC proxy settings
       10. Test system web proxy settings
       11. Test for transparent proxy detection via HTTP headers
       12. Test for authenticating proxy detection via HTTP 407 response
       13. Test Entra ID connectivity
       14. Test DiagnosticUri connectivity

.PARAMETER LogLevel
    Verbosity of logging output. Valid values: ERROR, WARNING, INFO, DEBUG, SUCCESS.

.PARAMETER BasePath
    Directory for the log file. Defaults to the current working directory.

.PARAMETER LogFileName
    Name of the log file. Defaults to GSAClientConnectivityChecker.log.

.EXAMPLE
    Invoke-GSAClientConnectivityCheck -LogLevel DEBUG

.EXAMPLE
    Invoke-GSAClientConnectivityCheck -LogLevel ERROR -BasePath C:\Logs
#>
    [CmdletBinding()]
    param (
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel    = "INFO",
        [string]$BasePath    = (Get-Location),
        [string]$LogFileName = "GSAClientConnectivityChecker.log"
    )

    # Initialize module-level logging state
    $script:LogLevel    = $LogLevel
    $script:LogFilePath = Join-Path -Path $BasePath -ChildPath $LogFileName

    try {
        if (-Not (Test-Path $BasePath)) {
            New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
        }
    }
    catch {
        Write-Log -Message "Failed to create directory at path: $BasePath. Error: $_" -Level "ERROR"
        throw
    }

    $testsPassed       = 0
    $testsFailed       = 0
    $testsWithWarnings = 0
    $testResults       = @{}

    Write-Log "========= GSA Client Connectivity Checker v. $script:ModuleVer Started ========="

    $gsaEndpoints = Get-GSAEndpoints -RegistryValueName "ForwardingProfile"
    if (-Not $gsaEndpoints) { return }

    $gsaMainEndpointAddrs = $gsaEndpoints.MainEndpoints
    $DiagnosticUris       = $gsaEndpoints.DiagnosticUris

    $tests = [ordered]@{
        "GSA Service Status"              = { Test-GSAServiceStatus }
        "Device Entra Status"             = { Test-DeviceEntraStatus }
        "GSA Primary Refresh Token"       = { Test-GSAPrimaryRefreshToken }
        "GSA Forwarding Profile Registry" = { Test-GSAForwardingProfileRegistry }
        "GSA Forwarding Profile Timestamp" = { Test-GSAForwardingProfileTimestamp }
        "Basic Internet connectivity"     = { Test-InternetConnectivity }
        "Proxy Detection"                 = { Test-ProxyDetection }
        "GSA Secure DNS Status"          = { Test-GSASecureDnsStatus }
        "GSA IPv6 Status"                = { Test-GSAIPv6Status }
        "DNS Resolution"                  = { param($param1) Test-DnsResolution -fqdnList $param1 }
        "Entra ID Connectivity"           = { Test-EntraIDConnectivity }
        "TLS Connectivity"               = { param($param1) Test-TLSConnection -fqdnList $param1 }
        "mTLS Connectivity"              = { param($param1) Test-mTLSConnection -fqdnList $param1 }
        "Diagnostics Connectivity"       = { param($param1) Test-DiagnosticUris -DiagnosticUris $param1 }
        "GSA Synthetic Routes"           = { Test-GSASyntheticRoutes }
        "GSA Private DNS Resolver"       = { Test-GSAPrivateDnsResolver }
        "GSA Event Log"                  = { Test-GSAEventLog }
    }

    $testParams = [ordered]@{
        "DNS Resolution"           = @{ param1 = $gsaMainEndpointAddrs }
        "TLS Connectivity"         = @{ param1 = $gsaMainEndpointAddrs }
        "mTLS Connectivity"        = @{ param1 = $gsaMainEndpointAddrs }
        "Diagnostics Connectivity" = @{ param1 = $DiagnosticUris }
    }

    foreach ($testName in $tests.Keys) {
        Write-Log -Message "===== Executing: $testName =========" -Level "INFO"
        $scriptBlock = $tests[$testName]
        $params      = $testParams[$testName]

        $result = if ($params) { & $scriptBlock @params } else { & $scriptBlock }
        # If a test function leaked extra pipeline output, extract the PSCustomObject
        if ($result -is [array]) {
            $result = $result | Where-Object { $_ -is [PSCustomObject] } | Select-Object -Last 1
        }
        $testResults[$testName] = $result

        if ($result -is [PSCustomObject]) {
            if ($result.Warnings -gt 0) {
                Write-Log "===== $testName : WARNINGS =========" "WARNING"
                $testsWithWarnings++
            }
            if ($result.Passed -eq $true) {
                Write-Log "===== $testName : PASSED =========" "SUCCESS"
                $testsPassed++
            } elseif ($result.Passed -eq $false) {
                Write-Log "===== $testName : FAILED =========" "ERROR"
                $testsFailed++
            }
        } else {
            if ($result -eq $true) {
                Write-Log "===== $testName : PASSED =========" "SUCCESS"
                $testsPassed++
            } elseif ($result -eq $false) {
                Write-Log "===== $testName : FAILED =========" "ERROR"
                $testsFailed++
            }
        }
    }

    Write-Log "========= GSA Client Connectivity Check Completed =========" "INFO"

    $summaryTable = @()
    foreach ($testName in $testResults.Keys) {
        $result = if ($testResults[$testName] -is [PSCustomObject]) {
            if ($testResults[$testName].Passed -eq $true) { "PASSED" } else { "FAILED" }
        } else {
            if ($testResults[$testName] -eq $true) { "PASSED" } else { "FAILED" }
        }
        $warnings = if ($testResults[$testName] -is [PSCustomObject] -and $testResults[$testName].Warnings) {
            $testResults[$testName].Warnings
        } else { 0 }

        $summaryTable += [PSCustomObject]@{
            TestName = $testName
            Result   = $result
            Warnings = $warnings
        }
    }

    Write-Log "Test Results Summary:" "INFO"
    $summaryTable | Format-Table -AutoSize | Out-String -Stream | ForEach-Object { Write-Log $_ "INFO" }

    Write-Log "Summary: $testsPassed tests passed, $testsFailed tests failed, $testsWithWarnings tests with warnings." "INFO"

    if ($testsFailed -eq 0 -and $testsWithWarnings -eq 0) {
        Write-Log "All tests passed successfully!" "SUCCESS"
    } elseif ($testsFailed -eq 0) {
        Write-Log "All tests passed, but some tests generated warnings. Please review the logs for details." "WARNING"
    } else {
        Write-Log "Some tests failed. Please review the logs for details." "ERROR"
    }
}

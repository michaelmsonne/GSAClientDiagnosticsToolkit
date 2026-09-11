#
# Function: Invoke-GSAClientConnectivityCheck
# Public function for the GSA client diagnostics toolkit.
#
function Invoke-GSAClientConnectivityCheck
{
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
	Name of the log file. Defaults to GSAClientDiagnosticsToolkit.log.

.EXAMPLE
	Invoke-GSAClientConnectivityCheck -LogLevel DEBUG

.EXAMPLE
	Invoke-GSAClientConnectivityCheck -LogLevel ERROR -BasePath C:\Logs
#>
	[CmdletBinding()]
	param (
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel = "INFO",
		[string]$BasePath = (Get-Location),
		[string]$LogFileName = "GSAClientDiagnosticsToolkit.log"
	)

	# Initialize module-level logging state
	$script:LogLevel = $LogLevel

	try
    {
		if (-Not (Test-Path $BasePath))
        {
			New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
		}
	}
	catch
    {
		Write-Log -Message "Failed to create directory at path: $BasePath. Error: $($_.Exception.Message)" -Level "ERROR"
		throw
	}

	# Resolve to an absolute path so the log location does not depend on the current working directory
	$BasePath = (Resolve-Path -Path $BasePath).ProviderPath
	$script:LogFilePath = Join-Path -Path $BasePath -ChildPath $LogFileName

	$testsPassed = 0
	$testsFailed = 0
	$testsWithWarnings = 0
	$testResults = @{}

	Write-Log "========= GSA Client Connectivity Checker v. $script:ModuleVer Started ========="
	Write-Log "Log file    : $script:LogFilePath"
	Write-Log "Device Name : $env:COMPUTERNAME"
	Write-Log "User Account: $(Get-GSACurrentUserUPN)"

	$gsaEndpoints = Get-GSAEndpoints -RegistryValueName "ForwardingProfile"
	if (-Not $gsaEndpoints)
    { return }

	$gsaMainEndpointAddrs = $gsaEndpoints.MainEndpoints
	$DiagnosticUris = $gsaEndpoints.DiagnosticUris

	$tests = [ordered]@{
		"GSA Service Status"               = { Test-GSAServiceStatus }
		"Device Entra Status"              = { Test-DeviceEntraStatus }
		"GSA Primary Refresh Token"        = { Test-GSAPrimaryRefreshToken }
		"GSA Forwarding Profile Registry"  = { Test-GSAForwardingProfileRegistry }
		"GSA Forwarding Profile Timestamp" = { Test-GSAForwardingProfileTimestamp -PassThru }
		"Basic Internet connectivity"      = { Test-InternetConnectivity }
		"Proxy Detection"                  = { Test-ProxyDetection -PassThru }
		"GSA Secure DNS Status"            = { Test-GSASecureDnsStatus }
		"GSA IPv6 Status"                  = { Test-GSAIPv6Status -PassThru }
		"DNS Resolution"                   = { param($param1) Test-DnsResolution -fqdnList $param1 }
		"Entra ID Connectivity"            = { Test-EntraIDConnectivity }
		"TLS Connectivity"                 = { param($param1) Test-TLSConnection -fqdnList $param1 }
		"mTLS Connectivity"                = { param($param1) Test-mTLSConnection -fqdnList $param1 -PassThru }
		"Diagnostics Connectivity"         = { param($param1) Test-DiagnosticUris -DiagnosticUris $param1 }
		"GSA Synthetic Routes"             = { Test-GSASyntheticRoutes -PassThru }
		"GSA Private DNS Resolver"         = { Test-GSAPrivateDnsResolver }
		"GSA Event Log"                    = { Test-GSAEventLog -PassThru }
	}

	$testParams = [ordered]@{
		"DNS Resolution"           = @{ param1 = $gsaMainEndpointAddrs }
		"TLS Connectivity"         = @{ param1 = $gsaMainEndpointAddrs }
		"mTLS Connectivity"        = @{ param1 = $gsaMainEndpointAddrs }
		"Diagnostics Connectivity" = @{ param1 = $DiagnosticUris }
	}

	foreach ($testName in $tests.Keys)
    {
		Write-Log -Message "===== Executing: $testName =========" -Level "INFO"
		$scriptBlock = $tests[$testName]
		$params = $testParams[$testName]

		$script:_testResult = $null
		$result = if ($params) { & $scriptBlock @params } else { & $scriptBlock }
		if ($null -eq $result -and $null -ne $script:_testResult)
        { $result = $script:_testResult }
		# If a test function leaked extra pipeline output, extract the PSCustomObject
		if ($result -is [array])
        {
			$result = $result | Where-Object { $_ -is [PSCustomObject] } | Select-Object -Last 1
		}
		$testResults[$testName] = $result

		if ($result -is [PSCustomObject])
        {
			if ($result.Warnings -gt 0)
            {
				Write-Log "===== $testName : WARNINGS =========" "WARNING"
				$testsWithWarnings++
			}
			if ($result.Passed -eq $true)
            {
				Write-Log "===== $testName : PASSED =========" "SUCCESS"
				$testsPassed++
			}
			elseif ($result.Passed -eq $false) {
				Write-Log "===== $testName : FAILED =========" "ERROR"
				$testsFailed++
			}
		}
		else
        {
			if ($result -eq $true)
            {
				Write-Log "===== $testName : PASSED =========" "SUCCESS"
				$testsPassed++
			}
			elseif ($result -eq $false) {
				Write-Log "===== $testName : FAILED =========" "ERROR"
				$testsFailed++
			}
		}
	}

	Write-Log "========= GSA Client Connectivity Check Completed =========" "INFO"

	$summaryTable = @()
	foreach ($testName in $testResults.Keys)
    {
		$result = if ($testResults[$testName] -is [PSCustomObject]) {
			if ($testResults[$testName].Passed -eq $true)
            { "PASSED" } else { "FAILED" }
		}
		else
        {
			if ($testResults[$testName] -eq $true)
            { "PASSED" } else { "FAILED" }
		}
		$warnings = if ($testResults[$testName] -is [PSCustomObject] -and $testResults[$testName].Warnings) {
			$testResults[$testName].Warnings
		}
		else
        { 0 }

		$summaryTable += [PSCustomObject]@{
			TestName = $testName
			Result   = $result
			Warnings = $warnings
		}
	}

	Write-Log "Test Results Summary:" "INFO"

	$nameWidth   = [Math]::Max((($summaryTable.TestName | Measure-Object -Property Length -Maximum).Maximum), "Test Name".Length)
	$resultWidth = [Math]::Max(6, "Result".Length)
	$warnWidth   = [Math]::Max(8, "Warnings".Length)

	# ASCII-only borders/icons - Windows PowerShell 5.1 reads .ps1 files using the system codepage
	# without a UTF-8 BOM, so box-drawing/emoji characters can get mangled on save/load.
	$topBorder    = "+---+-$('-' * $nameWidth)-+-$('-' * $resultWidth)-+-$('-' * $warnWidth)-+"
	$midBorder    = "+---+-$('-' * $nameWidth)-+-$('-' * $resultWidth)-+-$('-' * $warnWidth)-+"
	$bottomBorder = "+---+-$('-' * $nameWidth)-+-$('-' * $resultWidth)-+-$('-' * $warnWidth)-+"
	$rowFormat    = "| {0} | {1,-$nameWidth} | {2,-$resultWidth} | {3,$warnWidth} |"

	Write-Log $topBorder "INFO" -NoPrefix -Color DarkGray
	Write-Log ($rowFormat -f " ", "Test Name", "Result", "Warnings") "INFO" -NoPrefix -Color White
	Write-Log $midBorder "INFO" -NoPrefix -Color DarkGray

	foreach ($row in $summaryTable)
    {
		$icon = if ($row.Result -eq 'FAILED') { 'X' } elseif ($row.Warnings -gt 0) { '!' } else { '*' }
		$rowColor = if ($row.Result -eq 'FAILED') { 'Red' } elseif ($row.Warnings -gt 0) { 'Yellow' } else { 'Green' }
		Write-Log ($rowFormat -f $icon, $row.TestName, $row.Result, $row.Warnings) "INFO" -NoPrefix -Color $rowColor
	}

	Write-Log $bottomBorder "INFO" -NoPrefix -Color DarkGray

	Write-Log "Summary: $testsPassed tests passed, $testsFailed tests failed, $testsWithWarnings tests with warnings." "INFO"

	if ($testsFailed -eq 0 -and $testsWithWarnings -eq 0)
    {
		Write-Log "All tests passed successfully!" "SUCCESS"
	}
	elseif ($testsFailed -eq 0) {
		Write-Log "All tests passed, but some tests generated warnings. Please review the logs for details." "WARNING"
	}
	else
    {
		Write-Log "Some tests failed. Please review the logs for details." "ERROR"
	}
}

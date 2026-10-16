#
# Function: Invoke-GSAClientConnectivityCheck
# Public function for the GSA client diagnostics toolkit.
#
function Invoke-GSAClientConnectivityCheck {
	<#
.SYNOPSIS
	Runs all GSA Client connectivity, proxy, health probe, and mTLS checks.

.DESCRIPTION
	Executes the full diagnostic suite:
		1. GSA Service status
		2. Device Entra join/registration status
		3. GSA Primary Refresh Token status
		4. GSA Forwarding Profile registry contents
		5. GSA Forwarding Profile timestamp/freshness
		6. Basic internet connectivity
		7. Proxy detection (transparent/authenticating proxy via HTTP headers/407 response)
		8. GSA Secure DNS status
		9. GSA IPv6 status
	   10. DNS resolution for each FQDN
	   11. Tenant Internet DNS Resolution detection
	   12. Entra ID connectivity
	   13. TLS connectivity to each FQDN
	   14. mTLS connectivity to each FQDN
	   15. DiagnosticUri connectivity
	   16. GSA synthetic routes
	   17. GSA private DNS resolver
	   18. GSA event log

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

	try {
		if (-Not (Test-Path $BasePath)) {
			New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
		}
	}
	catch {
		Write-Log -Message "Failed to create directory at path: $BasePath. Error: $($_.Exception.Message)" -Level "ERROR"
		throw
	}

	# Resolve to an absolute path so the log location does not depend on the current working directory
	$BasePath = (Resolve-Path -Path $BasePath).ProviderPath
	$script:LogFilePath = Join-Path -Path $BasePath -ChildPath $LogFileName

	# Initialize the test result counters and storage.
	$testsPassed = 0
	$testsFailed = 0
	$testsWithWarnings = 0
	$testResults = @{}

	# Log the start of the connectivity check.
	Write-Log "========= GSA Client Connectivity Checker v. $script:ModuleVer Started ========="
	Write-Log "Log file    : $script:LogFilePath"
	Write-Log "Device Name : $env:COMPUTERNAME"
	Write-Log "User Account: $(Get-GSACurrentUserUPN)"

	# Retrieve the GSA endpoints from the registry.
	$gsaEndpoints = Get-GSAEndpoints -RegistryValueName "ForwardingProfile"
	if (-Not $gsaEndpoints)
	{ return }

	# Extract the main endpoint addresses and diagnostic URIs from the retrieved GSA endpoints.
	$gsaMainEndpointAddrs = $gsaEndpoints.MainEndpoints
	$DiagnosticUris = $gsaEndpoints.DiagnosticUris

	# Define the set of connectivity tests to be executed by main function.
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
		"Tenant Internet DNS Resolution"     = { Test-GSATenantInternetDnsResolution }
		"Entra ID Connectivity"            = { Test-EntraIDConnectivity }
		"TLS Connectivity"                 = { param($param1) Test-TLSConnection -fqdnList $param1 }
		"mTLS Connectivity"                = { param($param1) Test-mTLSConnectivity -fqdnList $param1 -PassThru }
		"Diagnostics Connectivity"         = { param($param1) Test-GSADiagnosticUriConnectivity -DiagnosticUris $param1 }
		"GSA Synthetic Routes"             = { Test-GSASyntheticRoutes -PassThru }
		"GSA Private DNS Resolver"         = { Test-GSAPrivateDnsResolver }
		"GSA Event Log"                    = { Test-GSAEventLog -PassThru }
	}

	# Define the parameters for the connectivity tests that require them.
	$testParams = [ordered]@{
		"DNS Resolution"           = @{ param1 = $gsaMainEndpointAddrs }
		"TLS Connectivity"         = @{ param1 = $gsaMainEndpointAddrs }
		"mTLS Connectivity"        = @{ param1 = $gsaMainEndpointAddrs }
		"Diagnostics Connectivity" = @{ param1 = $DiagnosticUris }
	}

	# Execute each connectivity test in sequence, passing the required parameters if applicable.
	foreach ($testName in $tests.Keys) {
		Write-Log -Message "===== Executing: $testName =========" -Level "INFO"
		$scriptBlock = $tests[$testName]
		$params = $testParams[$testName]

		# Initialize the test result variable for the current test.
		$script:_testResult = $null
		$result = if ($params) { & $scriptBlock @params } else { & $scriptBlock }
		if ($null -eq $result -and $null -ne $script:_testResult)
		{ $result = $script:_testResult }
		# If a test function leaked extra pipeline output, extract the PSCustomObject
		if ($result -is [array]) {
			$result = $result | Where-Object { $_ -is [PSCustomObject] } | Select-Object -Last 1
		}
		$testResults[$testName] = $result

		# View the results type output
		if ($result -is [PSCustomObject]) {
			if ($result.Warnings -gt 0) {
				Write-Log "===== $testName : WARNINGS =========" "WARNING"
				$testsWithWarnings++
			}
			if ($result.Passed -eq $true) {
				Write-Log "===== $testName : PASSED =========" "SUCCESS"
				$testsPassed++
			}
			elseif ($result.Passed -eq $false) {
				Write-Log "===== $testName : FAILED =========" "ERROR"
				$testsFailed++
			}
		}
		else {
			if ($result -eq $true) {
				Write-Log "===== $testName : PASSED =========" "SUCCESS"
				$testsPassed++
			}
			elseif ($result -eq $false) {
				Write-Log "===== $testName : FAILED =========" "ERROR"
				$testsFailed++
			}
		}
	}

	# Log the completion of the connectivity check.
	Write-Log "========= GSA Client Connectivity Check Completed =========" "INFO"

	# Prepare the summary table for the test results.
	$summaryTable = @()
	foreach ($testName in $testResults.Keys) {
		$result = if ($testResults[$testName] -is [PSCustomObject]) {
			if ($testResults[$testName].Passed -eq $true)
			{ "PASSED" } else { "FAILED" }
		}
		else {
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

	$nameWidth = [Math]::Max((($summaryTable.TestName | Measure-Object -Property Length -Maximum).Maximum), "Test Name".Length)
	$resultWidth = [Math]::Max(6, "Result".Length)
	$warnWidth = [Math]::Max(8, "Warnings".Length)

	# ASCII-only borders/icons - Windows PowerShell 5.1 reads .ps1 files using the system codepage
	# without a UTF-8 BOM, so box-drawing/emoji characters can get mangled on save/load.
	$topBorder = "+---+-$('-' * $nameWidth)-+-$('-' * $resultWidth)-+-$('-' * $warnWidth)-+"
	$midBorder = "+---+-$('-' * $nameWidth)-+-$('-' * $resultWidth)-+-$('-' * $warnWidth)-+"
	$bottomBorder = "+---+-$('-' * $nameWidth)-+-$('-' * $resultWidth)-+-$('-' * $warnWidth)-+"
	$rowFormat = "| {0} | {1,-$nameWidth} | {2,-$resultWidth} | {3,$warnWidth} |"

	Write-Log $topBorder "INFO" -NoPrefix -Color DarkGray
	Write-Log ($rowFormat -f " ", "Test Name", "Result", "Warnings") "INFO" -NoPrefix -Color White
	Write-Log $midBorder "INFO" -NoPrefix -Color DarkGray

	# Iterate through each row in the summary table and log the test results with appropriate icons and colors.
	foreach ($row in $summaryTable) {
		$icon = if ($row.Result -eq 'FAILED') { 'X' } elseif ($row.Warnings -gt 0) { '!' } else { '*' }
		$rowColor = if ($row.Result -eq 'FAILED') { 'Red' } elseif ($row.Warnings -gt 0) { 'Yellow' } else { 'Green' }
		Write-Log ($rowFormat -f $icon, $row.TestName, $row.Result, $row.Warnings) "INFO" -NoPrefix -Color $rowColor
	}

	Write-Log $bottomBorder "INFO" -NoPrefix -Color DarkGray

	Write-Log "Summary: $testsPassed tests passed, $testsFailed tests failed, $testsWithWarnings tests with warnings." "INFO"

	# Provide a textual summary of the overall test results.
	if ($testsFailed -eq 0 -and $testsWithWarnings -eq 0) {
		Write-Log "All tests passed successfully!" "SUCCESS"
	}
	elseif ($testsFailed -eq 0) {
		Write-Log "All tests passed, but some tests generated warnings. Please review the logs for details." "WARNING"
	}
	else {
		Write-Log "Some tests failed. Please review the logs for details." "ERROR"
	}
}

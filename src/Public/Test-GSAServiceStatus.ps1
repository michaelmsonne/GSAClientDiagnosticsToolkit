#
# Function: Test-GSAServiceStatus
# Checks that all required Global Secure Access Windows services are running.
#
function Test-GSAServiceStatus
{
	<#
.SYNOPSIS
	Verifies that all required Global Secure Access Windows services are running.
.DESCRIPTION
	First verifies the GSA Client is installed (GlobalSecureAccessTunnelingService must exist),
	then checks the following services are in the Running state:
		- GlobalSecureAccessTunnelingService      (Tunneling)
		- GlobalSecureAccessClientManagerService  (Client Manager)
		- GlobalSecureAccessEngineService         (Engine)
		- GlobalSecureAccessDriver                (Driver)
		- GlobalSecureAccessPolicyRetrieverService / GlobalSecureAccessForwardingProfileService (Forwarding Profile)
#>
	[CmdletBinding()]
	param (
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	$allTestsPassed = $true

	# Verify GSA is installed before checking individual service states
	$gsaInstallPath = "$env:ProgramFiles\Global Secure Access Client"
	if (-not (Test-Path $gsaInstallPath))
    {
		Write-Log "Global Secure Access Client does not appear to be installed on this machine ('$gsaInstallPath' not found). Install the client from the Entra portal." "ERROR"
		$script:_testResult = [PSCustomObject]@{ Passed = $false; Warnings = 0 }
		return
	}
	Write-Log "Global Secure Access Client installation found at: $gsaInstallPath" "SUCCESS"

	# Fixed-name services that must each be Running
	$services = @(
		@{ Name = 'GlobalSecureAccessTunnelingService'; DisplayName = 'Tunneling Service' }
		@{ Name = 'GlobalSecureAccessClientManagerService'; DisplayName = 'Client Manager Service' }
		@{ Name = 'GlobalSecureAccessEngineService'; DisplayName = 'Engine Service' }
		@{ Name = 'GlobalSecureAccessDriver'; DisplayName = 'Driver Service' }
	)

	# Check the status of each required service and log the results.
	foreach ($svc in $services)
    {
		Write-Log "Checking $($svc.DisplayName) ($($svc.Name))..." "INFO"
		$svcObj = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
		if (-not $svcObj)
        {
			Write-Log "$($svc.DisplayName) ($($svc.Name)) is not installed/registered on this machine." "ERROR"
			$allTestsPassed = $false
		} elseif ($svcObj.Status -eq 'Running') {
			Write-Log "$($svc.DisplayName) is running." "SUCCESS"
			if ($script:LogLevel -eq "DEBUG")
            {
				Write-Log "  StartType: $($svcObj.StartType)" "DEBUG"
			}
		} else {
			Write-Log "$($svc.DisplayName) ($($svc.Name)) is not running (Status: $($svcObj.Status)). Ensure the service is started." "ERROR"
			$allTestsPassed = $false
		}
	}

	# Forwarding Profile Service - either the old or new service name may be present depending on client version
	Write-Log "Checking Forwarding Profile Service..." "INFO"
	$fpSvc = Get-Service -Name 'GlobalSecureAccessPolicyRetrieverService'  -ErrorAction SilentlyContinue
	$fpSvc2 = Get-Service -Name 'GlobalSecureAccessForwardingProfileService' -ErrorAction SilentlyContinue
	if (-not $fpSvc -and -not $fpSvc2)
    {
		Write-Log "Forwarding Profile Service is not installed/registered on this machine (neither GlobalSecureAccessForwardingProfileService nor GlobalSecureAccessPolicyRetrieverService found)." "ERROR"
		$allTestsPassed = $false
	} elseif ($fpSvc.Status -eq 'Running' -or $fpSvc2.Status -eq 'Running') {
		Write-Log "Forwarding Profile Service is running." "SUCCESS"
		if ($script:LogLevel -eq "DEBUG")
        {
			$running = if ($fpSvc.Status -eq 'Running') { $fpSvc } else { $fpSvc2 }
			Write-Log "  Name: $($running.Name), StartType: $($running.StartType)" "DEBUG"
		}
	} else {
		Write-Log "Forwarding Profile Service is not running (Status: $(if ($fpSvc) { $fpSvc.Status } else { $fpSvc2.Status })). Ensure GlobalSecureAccessForwardingProfileService (or GlobalSecureAccessPolicyRetrieverService) is started." "ERROR"
		$allTestsPassed = $false
	}

	$script:_testResult = [PSCustomObject]@{ Passed = $allTestsPassed; Warnings = 0 }
}

#
# Function: Test-GSAHyperVExternalSwitch
# Detects a Hyper-V external virtual switch on the host, a documented GSA limitation:
# the Windows client doesn't currently support host machines that have one (internal/private
# switches are fine, and VMs running the client themselves are fully supported).
#
function Test-GSAHyperVExternalSwitch
{
	<#
.SYNOPSIS
	Detects a Hyper-V external virtual switch on this host, a documented GSA client limitation.
.DESCRIPTION
	Mirrors the "No Hyper-V external virtual switch detected" test from the GSA client's built-in
	Advanced Diagnostics Health check. Per Microsoft Learn, the Global Secure Access Windows client
	doesn't currently support host machines that have a Hyper-V EXTERNAL virtual switch (an internal
	or private virtual switch is fine, and installing the client inside a VM to tunnel that VM's own
	traffic is fully supported - this check only looks at the host's switch type).
	Confirmed via Process Monitor analysis: the Advanced Diagnostics tool itself runs
	'powershell.exe -WindowStyle Hidden Get-VMSwitch -SwitchType External' as part of its health check.
	If the Hyper-V PowerShell module/feature isn't installed, this check is not applicable and passes.
.PARAMETER PassThru
	Return the $true/$false test result. By default nothing is returned - only logged.
.PARAMETER LogLevel
	Sets the minimum log level written by the module. Valid values are ERROR, WARNING, INFO, DEBUG, and SUCCESS.
.OUTPUTS
	System.Boolean when -PassThru is specified. No output is returned by default.
.EXAMPLE
	Test-GSAHyperVExternalSwitch
.LINK
	https://learn.microsoft.com/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health-check#no-hyper-v-external-virtual-switch-detected
#>
	[CmdletBinding()]
	param (
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	Write-Log "Checking for a Hyper-V external virtual switch on this host - the GSA client doesn't support that configuration..." "INFO"

	$externalSwitches = @()
	try
    {
		$externalSwitches = @(Get-VMSwitch -SwitchType External -ErrorAction Stop)
	}
	catch
    {
		Write-Log "Hyper-V isn't installed/available on this host ($($_.Exception.Message)). This check is not applicable." "SUCCESS"
		if ($PassThru)
		{ return $true }
		return
	}

	if ($externalSwitches.Count -eq 0)
    {
		Write-Log "No Hyper-V external virtual switch was found on this host." "SUCCESS"
		if ($PassThru)
		{ return $true }
		return
	}

	foreach ($vmSwitch in $externalSwitches)
    {
		Write-Log "Hyper-V external virtual switch detected: '$($vmSwitch.Name)' (bound to '$($vmSwitch.NetAdapterInterfaceDescription)')." "WARNING"
	}
	Write-Log "Recommended action: the GSA Windows client doesn't currently support host machines with a Hyper-V external virtual switch. If this host also runs the GSA client, consider removing the external switch (an internal/private switch is supported), or install the GSA client inside the VM(s) instead to tunnel their own traffic." "WARNING"

	if ($PassThru)
    { return [PSCustomObject]@{ Passed = $true; Warnings = 1 } }
}

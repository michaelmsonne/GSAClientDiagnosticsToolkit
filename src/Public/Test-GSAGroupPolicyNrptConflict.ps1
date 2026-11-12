#
# Function: Test-GSAGroupPolicyNrptConflict
# Detects Group Policy-applied Name Resolution Policy Table (NRPT) rules
# (HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\DnsPolicyConfig), a documented GSA
# known limitation: when present (even as an empty rule list left over from an older Windows
# version), these Group Policy NRPT rules override the local NRPT rules the GSA client configures
# for private DNS, breaking Private Access DNS resolution.
#
function Test-GSAGroupPolicyNrptConflict {
	<#
.SYNOPSIS
	Detects Group Policy-applied NRPT rules that override the GSA client's local private DNS NRPT rules.
.DESCRIPTION
	The Global Secure Access client doesn't support Name Resolution Policy Table (NRPT) rules
	applied via Group Policy. To support private DNS, the client configures local NRPT rules on
	the device; if NRPT rules are also configured in Group Policy, they override the client's
	local NRPT rules and private DNS stops working. This also applies to an empty NRPT rule list
	left behind in the registry.pol file when rules were configured and deleted on an older
	version of Windows - an empty list still overrides the local NRPT rules.
	This check looks for the registry key HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\DnsPolicyConfig,
	which only exists when Group Policy has applied NRPT rules to the device. This is a fully
	local/offline check (registry only).
.PARAMETER FindSourceGpo
	When a conflict is found, also searches the domain's SYSVOL Policies share for registry.pol
	files referencing 'dnspolicyconfig' to help locate the source GPO. The SYSVOL path is
	auto-detected from this device's domain membership and shown for confirmation - press Enter
	to accept it or type a different path - before the (potentially slow) recursive search runs.
	Requires domain connectivity/permissions to read SYSVOL; has no effect when no conflict is found.
.PARAMETER PassThru
	Return the $true/$false test result. By default nothing is returned - only logged.
.PARAMETER LogLevel
	Sets the minimum log level written by the module. Valid values are ERROR, WARNING, INFO, DEBUG, and SUCCESS.
.OUTPUTS
	System.Boolean when -PassThru is specified. No output is returned by default.
.EXAMPLE
	Test-GSAGroupPolicyNrptConflict
.EXAMPLE
	Test-GSAGroupPolicyNrptConflict -FindSourceGpo
.LINK
	https://learn.microsoft.com/en-us/entra/global-secure-access/reference-current-known-limitations?tabs=windows-client#name-resolution-policy-table-rules-in-group-policy-not-supported
#>
	[CmdletBinding()]
	param (
		[switch]$FindSourceGpo,
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
	{ $script:LogLevel = $LogLevel }

	$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\DnsPolicyConfig"

	Write-Log "Checking for Group Policy-applied NRPT rules at '$policyPath' that can override GSA's local private DNS NRPT rules..." "INFO"

	if (-not (Test-Path -Path $policyPath)) {
		Write-Log "No Group Policy-applied NRPT configuration was found. GSA private DNS is not affected by this known limitation." "SUCCESS"
		if ($PassThru)
		{ return $true }
		return
	}

	# The key exists, meaning Group Policy is applying NRPT rules (or an empty list), which overrides the client's local rules.
	$ruleKeys = @(Get-ChildItem -Path $policyPath -ErrorAction SilentlyContinue)

	if ($ruleKeys.Count -eq 0) {
		Write-Log "Group Policy-applied NRPT configuration exists at '$policyPath' but contains no rules. This is a known legacy artifact (an empty NRPT rule list left behind after rules were configured and deleted on an older Windows version) that still overrides the GSA client's local NRPT rules and breaks private DNS." "ERROR"
	}
	else {
		Write-Log "Group Policy-applied NRPT configuration exists at '$policyPath' with $($ruleKeys.Count) rule(s). These Group Policy NRPT rules override the GSA client's local NRPT rules, and private DNS will not work while this GPO is applied." "ERROR"
	}

	Write-Log "Recommended action: Run 'gpresult /h GPReport.html' on this device (or search registry.pol files in SYSVOL for 'dnspolicyconfig') to find the source GPO. If the NRPT section is empty, create/apply/delete a fictive rule to clear the legacy artifact. If it contains real rules, confirm whether they're still required - they're incompatible with GSA private DNS while applied to a device running the GSA client." "WARNING"

	if ($FindSourceGpo)
	{ Find-GSAGroupPolicyNrptSourceGpo }

	if ($PassThru)
	{ return $false }
}

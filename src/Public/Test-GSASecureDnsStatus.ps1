#
# Function: Test-GSASecureDnsStatus
# Checks whether Secure DNS (DoH) is disabled in Edge, Chrome, and Firefox.
# GSA uses WFP to intercept DNS queries; DoH bypasses WFP so FQDN-based traffic
# rules cannot be matched and traffic is not tunneled.
#
function Test-GSASecureDnsStatus
{
	<#
.SYNOPSIS
	Verifies that Secure DNS (DNS-over-HTTPS) is disabled in Microsoft Edge, Google Chrome, and Mozilla Firefox.
.DESCRIPTION
	GSA intercepts DNS queries at the WFP layer to match FQDN-based forwarding rules.
	When DoH is active, DNS bypasses WFP and GSA cannot identify the destination,
	so traffic is not tunneled. Checks HKLM and HKCU policy registry keys for Edge/Chrome
	(DnsOverHttpsMode) and the HKLM GPO registry key for Firefox (DNSOverHTTPS\Enabled), per
	https://learn.microsoft.com/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health-check#secure-dns-disabled-in-browsers-microsoft-edge-chrome-firefox
	Disable DoH via Group Policy (DnsOverHttpsMode = off, or DNSOverHTTPS\Enabled = 0 for
	Firefox) or in browser settings.
#>
	[CmdletBinding()]
	param (
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	$allPassed = $true

	# Define the browsers and their corresponding policy registry paths to check for DoH settings.
	# Edge/Chrome expose a flat DnsOverHttpsMode string; Firefox's GPO template nests an Enabled
	# DWORD under a DNSOverHTTPS subkey instead (https://firefox-admin-docs.mozilla.org/reference/policies/dnsoverhttps/).
	$browsers = @(
		@{ Name = 'Microsoft Edge'; Paths = @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKCU:\SOFTWARE\Policies\Microsoft\Edge') }
		@{ Name = 'Google Chrome'; Paths = @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKCU:\SOFTWARE\Policies\Google\Chrome') }
		@{ Name = 'Mozilla Firefox'; Paths = @('HKLM:\SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS'); ValueName = 'Enabled' }
	)

	Write-Log "Checking Secure DNS (DoH) policy settings - GSA requires DoH to be disabled..." "INFO"

	# Iterate through each browser and check the DoH policy settings in the registry.
	foreach ($browser in $browsers)
    {
		$dohFound = $false
		foreach ($path in $browser.Paths)
        {
			if ($browser.ValueName)
            {
				# Firefox: DNSOverHTTPS\Enabled is a DWORD (1 = enabled via policy).
				$enabled = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).($browser.ValueName)
				if ($enabled -eq 1)
                {
					Write-Log "$($browser.Name): Secure DNS is enabled ($($browser.ValueName) = 1 at $path). GSA cannot acquire FQDN-based traffic when DoH is active. Set $($browser.ValueName) to 0 via Group Policy/policies.json or disable DoH in the browser." "WARNING"
					$dohFound = $true
					break
				}
			}
			else
            {
				$dohMode = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).DnsOverHttpsMode
				if ($dohMode -and $dohMode -ne "off")
                {
					Write-Log "$($browser.Name): Secure DNS is enabled (DnsOverHttpsMode = '$dohMode' at $path). GSA cannot acquire FQDN-based traffic when DoH is active. Set DnsOverHttpsMode to 'off' via Group Policy or disable DoH in the browser." "WARNING"
					$dohFound = $true
					break
				}
			}
		}
		if (-not $dohFound)
        {
			Write-Log "$($browser.Name): Secure DNS (DoH) is not enforced or is set to 'off'." "SUCCESS"
		}
	}

	return $allPassed
}

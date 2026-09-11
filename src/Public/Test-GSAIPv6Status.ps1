#
# Function: Test-GSAIPv6Status
# Checks whether IPv6 is enabled on active physical adapters.
# GSA does not support IPv6 traffic; when IPv6 is active, IPv6-based connections
# bypass the GSA tunnel and are sent directly.
#
function Test-GSAIPv6Status
{
	<#
.SYNOPSIS
	Checks whether IPv6 is enabled on active physical network adapters.
.DESCRIPTION
	GSA does not support IPv6 traffic. When IPv6 is enabled on an adapter,
	applications that connect via IPv6 will bypass the GSA tunnel entirely.
	Disable IPv6 (ms_tcpip6 binding) on physical adapters to ensure all traffic
	is routed through GSA. Virtual adapters (e.g., loopback, Hyper-V) are skipped.
#>
	[CmdletBinding()]
	param (
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	$warningsFound = $false

	Write-Log "Checking IPv6 binding on active physical network adapters - GSA does not support IPv6..." "INFO"

	try
    {
		# Virtual = $false excludes loopback / Hyper-V / VPN virtual adapters
		$adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }

		if (-not $adapters)
        {
			Write-Log "No active physical network adapters found." "WARNING"
			if ($PassThru) { return [PSCustomObject]@{ Passed = $true; Warnings = 1 } }
			return
		}

		foreach ($adapter in $adapters)
        {
			$binding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
			if ($binding.Enabled)
            {
				Write-Log "IPv6 is ENABLED on adapter '$($adapter.Name)'. Disable it to prevent IPv6 traffic from bypassing the GSA tunnel." "WARNING"
				if ($script:LogLevel -eq "DEBUG")
                {
					$v6addrs = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv6 -ErrorAction SilentlyContinue |
					Where-Object { $_.IPAddress -ne '::1' }
					foreach ($addr in $v6addrs)
                    {
						Write-Log "  IPv6 on '$($adapter.Name)': $($addr.IPAddress)/$($addr.PrefixLength)" "DEBUG"
					}
				}
				$warningsFound = $true
			}
			else
            {
				Write-Log "IPv6 is disabled on adapter '$($adapter.Name)'." "INFO"
			}
		}

		if (-not $warningsFound)
        {
			Write-Log "IPv6 is disabled on all active physical adapters." "SUCCESS"
			return $true
		}
		if ($PassThru) { return [PSCustomObject]@{ Passed = $true; Warnings = 1 } }
		return
	}
	catch
    {
		Write-Log "Failed to check IPv6 adapter bindings: $($_.Exception.Message)" "ERROR"
		return $false
	}
}

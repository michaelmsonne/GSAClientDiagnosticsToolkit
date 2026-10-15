#
# Function: Test-GSATenantInternetDnsOverride
# Validates tenant Internet forwarding DNS hostnames and detects local hosts-file overrides.
#
function Test-GSATenantInternetDnsOverride {
	<#
.SYNOPSIS
	Checks tenant Internet forwarding DNS hostnames for local hosts-file override issues.
.DESCRIPTION
	Reads tenantId from the locally cached ForwardingProfile registry JSON and validates:
		- <tenantId>.internet.client.globalsecureaccess.microsoft.com
		- <tenantId>.internet-backup.client.globalsecureaccess.microsoft.com
	For each hostname, validates that normal system resolution returns the expected synthetic
	`6.6.0.0/16` GSA address and logs the CNAME chain/aliases. It also compares with direct DNS
	(`Resolve-DnsName -NoHostsFile`) and checks the local hosts file to detect overrides.
.PARAMETER RegistryValueName
	Registry value containing the forwarding profile JSON. Defaults to ForwardingProfile.
.PARAMETER LogLevel
	Optional per-call log verbosity override.
#>
	[CmdletBinding()]
	param (
		[string]$RegistryValueName = "ForwardingProfile",
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
	{ $script:LogLevel = $LogLevel }

	function Get-DnsIPAddresses {
		param (
			[object[]]$Records
		)

		if (-Not $Records) {
			return @()
		}
		return @(
			$Records |
			Where-Object -FilterScript {
				$_.PSObject.Properties.Name -contains 'IPAddress' -and
				-Not [string]::IsNullOrWhiteSpace($_.IPAddress)
			} |
			Select-Object -ExpandProperty IPAddress -Unique
		)
	}

	function Get-HostsFileLinesForFqdn {
		param (
			[string]$Fqdn
		)

		$hostsPath = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
		if (-Not (Test-Path -LiteralPath $hostsPath)) { 
			return @()
		}

		$lines = @()
		try {
			$lines = @(Get-Content -LiteralPath $hostsPath -ErrorAction Stop)
		}
		catch {
			Write-Log "Could not read hosts file '$hostsPath': $($_.Exception.Message)" "WARNING"
			return @()
		}

		$matchingLines = @()
		foreach ($line in $lines) {
			if ([string]::IsNullOrWhiteSpace($line))
			{ continue }
			if ($line.TrimStart().StartsWith('#'))
			{ continue }

			$withoutInlineComment = ($line -replace '\s+#.*$', '').Trim()
			if ([string]::IsNullOrWhiteSpace($withoutInlineComment))
			{ continue }

			$parts = @($withoutInlineComment -split '\s+' | Where-Object -FilterScript { $_ })
			if ($parts.Count -lt 2)
			{ continue }

			$entryHostnames = @($parts[1..($parts.Count - 1)])
			if ($entryHostnames -icontains $Fqdn)
			{ $matchingLines += $line.Trim() }
		}

		return $matchingLines
	}

	Write-Log "Checking tenant Internet forwarding DNS hostnames for local override issues..." "INFO"

	$profileJson = Get-JsonFromRegistry -ValueName $RegistryValueName
	if (-Not $profileJson -or -Not $profileJson.policy -or [string]::IsNullOrWhiteSpace($profileJson.policy.tenantId)) {
		Write-Log "TenantId was not found in '$RegistryValueName' registry JSON. Cannot validate tenant Internet DNS hostnames." "ERROR"
		$script:_testResult = [PSCustomObject]@{ Passed = $false; Warnings = 0 }
		return
	}

	$tenantId = "$($profileJson.policy.tenantId)".Trim()
	$tenantFqdns = @(
		"$tenantId.internet.client.globalsecureaccess.microsoft.com",
		"$tenantId.internet-backup.client.globalsecureaccess.microsoft.com"
	)

	$syntheticRangeStart = 101056512 # 6.6.0.0
	$syntheticRangeEnd = 101122047   # 6.6.255.255
	$allPassed = $true

	foreach ($tenantFqdn in $tenantFqdns) {
		Write-Log "Validating tenant hostname '$tenantFqdn'..." "INFO"

		$realRecords = $null
		try {
			$realRecords = @(Resolve-DnsName -Name $tenantFqdn -NoHostsFile -ErrorAction Stop)
		}
		catch {
			Write-Log "Direct DNS lookup (NoHostsFile) failed for '$tenantFqdn': $($_.Exception.Message)" "ERROR"
			$allPassed = $false
			continue
		}

		$systemRecords = $null
		try {
			$systemRecords = @(Resolve-DnsName -Name $tenantFqdn -ErrorAction Stop)
		}
		catch {
			Write-Log "System DNS lookup failed for '$tenantFqdn': $($_.Exception.Message)" "ERROR"
			$allPassed = $false
			continue
		}

		$realIPs = @(Get-DnsIPAddresses -Records $realRecords)
		$systemIPs = @(Get-DnsIPAddresses -Records $systemRecords)
		if ($realIPs.Count -eq 0) {
			Write-Log "Direct DNS lookup for '$tenantFqdn' returned no A/AAAA records." "ERROR"
			$allPassed = $false
			continue
		}

		Write-Log "Direct DNS (NoHostsFile): $($realIPs -join ', ')" "INFO"
		if ($systemIPs.Count -gt 0) {
			Write-Log "System DNS: $($systemIPs -join ', ')" "INFO"
		}
		else {
			Write-Log "System DNS for '$tenantFqdn' returned no A/AAAA records." "ERROR"
			$allPassed = $false
			continue
		}

		$cnameRecords = @(
			$systemRecords |
			Where-Object -FilterScript {
				$_.PSObject.Properties.Name -contains 'QueryType' -and
				$_.QueryType -eq 'CNAME' -and
				$_.PSObject.Properties.Name -contains 'NameHost' -and
				-Not [string]::IsNullOrWhiteSpace($_.NameHost)
			} |
			Select-Object -ExpandProperty NameHost -Unique
		)
		if ($cnameRecords.Count -gt 0) {
			Write-Log "CNAME/alias targets: $($cnameRecords -join ' -> ')" "DEBUG"
		}

		$hostsFileLines = @(Get-HostsFileLinesForFqdn -Fqdn $tenantFqdn)
		if ($hostsFileLines.Count -gt 0) {
			Write-Log "Hosts-file override found for '$tenantFqdn'." "ERROR"
			foreach ($hostLine in $hostsFileLines)
			{ Write-Log "  hosts: $hostLine" "ERROR" }
			Write-Log "Recommended action: Remove this hosts-file entry so '$tenantFqdn' resolves to the real DNS IP." "WARNING"
			
			$allPassed = $false
		}

		$realIpSet = @($realIPs | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object -Unique)
		$systemIpSet = @($systemIPs | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object -Unique)
		$dnsDiff = @(Compare-Object -ReferenceObject $realIpSet -DifferenceObject $systemIpSet -CaseSensitive:$false)
		if ($dnsDiff.Count -gt 0) {
			Write-Log "System DNS differs from direct DNS for '$tenantFqdn'. This can indicate a local DNS override/interception path." "WARNING"
		}

		$syntheticSystemIPv4 = @(
			$systemIPs | Where-Object -FilterScript {
				$_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and
				(Test-GSAIPInRange -Start $syntheticRangeStart -End $syntheticRangeEnd -IPAddress $_)
			}
		)
		if ($syntheticSystemIPv4.Count -eq 0) {
			Write-Log "System DNS for '$tenantFqdn' did not return an expected synthetic 6.6.0.0/16 address." "ERROR"
			Write-Log "Expected output is similar to: Address: 6.6.x.x with aliases under ztna3p-*.ztna3p-msedge.net." "WARNING"
			$allPassed = $false
		}
		else {
			Write-Log "System DNS returned expected synthetic GSA address(es): $($syntheticSystemIPv4 -join ', ')." "SUCCESS"
		}

		$privateSystemIPv4 = @($systemIPs | Where-Object -FilterScript { Test-GSAIsPrivateIPv4 -IPAddress $_ })
		if ($privateSystemIPv4.Count -gt 0) {
			Write-Log "System DNS for '$tenantFqdn' includes private IPv4 address(es): $($privateSystemIPv4 -join ', ')." "ERROR"
			Write-Log "Expected result is synthetic GSA address(es) in 6.6.0.0/16, not RFC1918 private IPs." "WARNING"
			$allPassed = $false
		}
	}

	if ($allPassed) {
		Write-Log "Tenant Internet forwarding DNS hostnames resolve to real DNS addresses with no hosts-file override detected." "SUCCESS"
	}

	$script:_testResult = [PSCustomObject]@{ Passed = $allPassed; Warnings = 0 }
}
#
# Function: Test-GSAHomeNetworkSupport
# Public function for the GSA client diagnostics toolkit.
#
function Test-GSAHomeNetworkSupport {
	<#
.SYNOPSIS
	Checks whether Microsoft Entra Private Access home network support ("Allow local subnet bypass") is
	enabled for this client and flags directly connected subnets that overlap Private Access destinations.
.DESCRIPTION
	Home network support lets users reach resources on their directly connected local subnet (printer,
	router, local VM) while Private Access stays connected. It is enabled per Private Access traffic
	forwarding profile in Entra (Global Secure Access > Connect > Traffic forwarding > "Allow local subnet
	bypass"), and the client then offers the "Prefer Local Network" setting.

	This is a fully local/offline check against the forwarding profile the client received (the same
	policy the Entra setting is delivered through; it does not call Microsoft Graph). It checks:
		1. The Private Access channel was retrieved at all (profile enabled and user assigned).
		2. The channel carries the localNetwork setting, and that it is enabled
		   (localNetwork.isLocalNetworkFeatureEnabled). A missing setting usually means a client version
		   that doesn't support home network support yet.
		3. The device has at least one active adapter with an RFC1918 IPv4 address - only RFC1918 IPv4
		   subnets are supported (no IPv6, no routed networks behind the gateway).
		4. Whether a directly connected local subnet (adapter IP + mask) overlaps Private Access
		   destinations (IP rules that tunnel traffic). With "Prefer Local Network" on, matching traffic
		   is kept on the local network, so the corporate resource in the overlapping range becomes
		   unreachable through Private Access from that network.
	Note: Intelligent Local Access takes precedence over home network support when both apply, and the
	per-user "Prefer Local Network" toggle in the client is not stored in the forwarding profile, so it
	can't be verified here.
.PARAMETER RegistryValueName
	Registry value name containing the GSA JSON policy (default: ForwardingProfile).
.PARAMETER PassThru
	Return the $true/$false test result. By default nothing is returned - only logged. The result is
	$false when home network support is not enabled in the received profile.
.EXAMPLE
	Test-GSAHomeNetworkSupport
.EXAMPLE
	Test-GSAHomeNetworkSupport -PassThru
#>
	[CmdletBinding()]
	param (
		[string]$RegistryValueName = "ForwardingProfile",
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
	{ $script:LogLevel = $LogLevel }

	Write-Log "Checking Private Access home network support (Allow local subnet bypass)..." "INFO"

	# Load the GSA client configuration from the registry.
	$jsonContent = Get-JsonFromRegistry -ValueName $RegistryValueName
	if (-not $jsonContent) {
		Write-Log "Failed to load GSA client configuration from the registry." "ERROR"
		if ($PassThru)
		{ return $false }
		return
	}

	# Home network support is delivered on the Private Access channel only.
	$allChannels = @($jsonContent.policy.channels)
	Write-Log "Profile tenantId: $($jsonContent.policy.tenantId); policy id: $($jsonContent.policy.id); settingsVersion: $($jsonContent.settingsVersion); controlPlanePoliciesVersion: $($jsonContent.controlPlanePoliciesVersion)." "DEBUG"
	Write-Log "Profile contains $($allChannels.Count) channel(s): $(($allChannels | ForEach-Object { "$($_.name) [id=$($_.id), localNetwork=$(if ($null -ne $_.localNetwork) { $_.localNetwork | ConvertTo-Json -Compress } else { 'not present' })]" }) -join '; ')." "DEBUG"
	Write-Log "Profile contains $(@($jsonContent.policy.rules).Count) rule(s) in total." "DEBUG"
	$channel = $allChannels | Where-Object { $_.name -eq 'private' } | Select-Object -First 1
	if (-not $channel) {
		Write-Log "Private Access forwarding profile channel was not retrieved - home network support can't be evaluated." "ERROR"
		Write-Log "Recommended action: Ensure the Private Access forwarding profile is enabled and the user is assigned in Entra portal under Global Secure Access > Connect > Traffic forwarding." "WARNING"
		if ($PassThru)
		{ return $false }
		return
	}

	Write-Log "Private Access channel found: name='$($channel.name)', id='$($channel.id)', channelProfileName='$($channel.channelProfileName)', localNetwork=$($channel.localNetwork | ConvertTo-Json -Compress)." "DEBUG"
	if ($null -eq $channel.localNetwork -or $null -eq $channel.localNetwork.isLocalNetworkFeatureEnabled) {
		Write-Log "The Private Access profile received by the client doesn't contain the home network support (localNetwork) setting." "WARNING"
		Write-Log "Recommended action: Verify the device runs a Global Secure Access client version that supports home network support, then refresh the profile (delete the ForwardingProfileTimestamp registry value and restart GlobalSecureAccessForwardingProfileService)." "WARNING"
		if ($PassThru)
		{ return $false }
		return
	}

	if (-not [bool]$channel.localNetwork.isLocalNetworkFeatureEnabled) {
		Write-Log "Home network support is NOT enabled in the Private Access forwarding profile this client received (Allow local subnet bypass is off)." "WARNING"
		Write-Log "Recommended action: If users need local network access while Private Access is connected, enable 'Allow local subnet bypass' on the Private Access traffic forwarding profile in Entra > Global Secure Access > Connect > Traffic forwarding (v2 experience). Then refresh the client profile (delete the ForwardingProfileTimestamp registry value and restart GlobalSecureAccessForwardingProfileService) and turn on 'Prefer Local Network' in the client settings." "WARNING"
		if ($PassThru)
		{ return $false }
		return
	}
	Write-Log "Home network support is enabled in the Private Access forwarding profile (Allow local subnet bypass)." "SUCCESS"

	# Calculate the directly connected local subnets the same way the client does: adapter IP + mask.
	Write-Log "Calculating directly connected RFC1918 IPv4 subnets on active adapters..." "INFO"
	$localSubnets = @()
	$toDotted = {
		param([uint64]$Value)
		$b = [BitConverter]::GetBytes([uint32]$Value)
		[Array]::Reverse($b)
		([System.Net.IPAddress]::new($b)).IPAddressToString
	}
	try {
		$allAdapters = @(Get-NetAdapter -ErrorAction Stop)
		$activeAdapters = @($allAdapters | Where-Object { $_.Status -eq 'Up' })
		Write-Log "Found $($allAdapters.Count) network adapter(s), $($activeAdapters.Count) active: $(($allAdapters | ForEach-Object { "$($_.Name) [ifIndex=$($_.ifIndex), status=$($_.Status)]" }) -join '; ')." "DEBUG"
		foreach ($adapter in $activeAdapters) {
			$addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
			Write-Log "Adapter '$($adapter.Name)' has $($addresses.Count) IPv4 address(es): $(($addresses | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) -join ', ')." "DEBUG"
			foreach ($address in $addresses) {
				$ip = $address.IPAddress
				$prefix = [int]$address.PrefixLength
				if (-not $ip -or $ip -like '127.*' -or -not (Test-GSAIsPrivateIPv4 -IPAddress $ip)) {
					Write-Log "Skipping '$($adapter.Name)' address '$ip': not an RFC1918 IPv4 address (not eligible for home network support)." "DEBUG"
					continue
				}
				$ipBytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
				[Array]::Reverse($ipBytes)
				$ipValue = [uint64][BitConverter]::ToUInt32($ipBytes, 0)
				$hostBits = 32 - $prefix
				$maskValue = ([uint64]4294967295 -shl $hostBits) -band [uint64]4294967295
				$startValue = $ipValue -band $maskValue
				$endValue = $startValue -bor ($maskValue -bxor [uint64]4294967295)
				$startBytes = [BitConverter]::GetBytes([uint32]$startValue)
				[Array]::Reverse($startBytes)
				Write-Log "Adapter '$($adapter.Name)' $ip/$prefix -> mask $(& $toDotted $maskValue), subnet range $(& $toDotted $startValue) - $(& $toDotted $endValue) (numeric $startValue - $endValue)." "DEBUG"
				$localSubnets += [PSCustomObject]@{
					Adapter = $adapter.Name
					Subnet  = "$(([System.Net.IPAddress]::new($startBytes)).IPAddressToString)/$prefix"
					Start   = $startValue
					End     = $endValue
				}
			}
		}
	}
	catch {
		Write-Log "Failed to enumerate network adapter addresses: $($_.Exception.Message)" "ERROR"
		if ($PassThru)
		{ return $false }
		return
	}

	if ($localSubnets.Count -eq 0) {
		Write-Log "No active adapter has an RFC1918 IPv4 address, so home network support has no directly connected local subnet to apply to on this network (IPv6 and non-RFC1918 subnets are not supported)." "WARNING"
		if ($PassThru)
		{ return $true }
		return
	}
	foreach ($localSubnet in $localSubnets) {
		Write-Log "Directly connected local subnet on '$($localSubnet.Adapter)': $($localSubnet.Subnet)" "INFO"
	}

	# Look for Private Access destinations (tunneled IP rules) that overlap a local subnet.
	$privateRules = @($jsonContent.policy.rules) | Where-Object { $_.channelId -eq $channel.id -and $_.action -eq 'Tunnel' }
	$allPrivateRules = @($jsonContent.policy.rules) | Where-Object { $_.channelId -eq $channel.id }
	Write-Log "Private Access channel has $(@($allPrivateRules).Count) rule(s); $(@($privateRules).Count) with action 'Tunnel' are evaluated for overlap (actions: $((@($allPrivateRules) | Group-Object action | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '))." "DEBUG"
	$overlapFound = $false
	$unparsedRanges = 0
	foreach ($localSubnet in $localSubnets) {
		Write-Log "Evaluating Private Access IP rules against local subnet $($localSubnet.Subnet) on '$($localSubnet.Adapter)'..." "DEBUG"
		$overlapping = @()
		foreach ($rule in $privateRules) {
			$ranges = @($rule.matchingCriteria.address.ips) | Where-Object { $_ }
			$ruleAppId = if ($rule.appAuthorizationTokenContext.audienceScope -match 'api://([^/]+)') { $Matches[1] } else { 'n/a' }
			if ($ranges.Count -eq 0) {
				Write-Log "Rule $($rule.id) (App ID: $ruleAppId, order: $($rule.order)) has no IP ranges (FQDN rule) - skipped." "DEBUG"
				continue
			}
			foreach ($range in $ranges) {
				$rangeStart = ConvertTo-GSAIPv4Number -Value $range.start
				$rangeEnd = ConvertTo-GSAIPv4Number -Value $range.end
				if ($null -eq $rangeStart -or $null -eq $rangeEnd) {
					# IPv6 ranges are expected (home network support is IPv4 only); anything else is unrecognized
					if ($range.start.PSObject.Properties.Match('f').Count -eq 0 -or [int]$range.start.f -eq 4) {
						$unparsedRanges++
						Write-Log "Rule $($rule.id) (App ID: $ruleAppId): could not interpret IP range $($range | ConvertTo-Json -Compress)." "DEBUG"
					}
					else {
						Write-Log "Rule $($rule.id) (App ID: $ruleAppId): IPv6 range $($range | ConvertTo-Json -Compress) skipped (home network support is IPv4 only)." "DEBUG"
					}
					continue
				}
				$isOverlap = $rangeStart -le $localSubnet.End -and $rangeEnd -ge $localSubnet.Start
				Write-Log "Rule $($rule.id) (App ID: $ruleAppId, order: $($rule.order), hardening: $($rule.hardening), ports: $(($rule.matchingCriteria.ports | ForEach-Object { "$($_.start)-$($_.end)" }) -join ','), protocol: $($rule.matchingCriteria.protocol)) range $(& $toDotted $rangeStart) - $(& $toDotted $rangeEnd) vs $($localSubnet.Subnet): $(if ($isOverlap) { 'OVERLAP' } else { 'no overlap' })." "DEBUG"
				if ($isOverlap) {
					$overlapping += $rule
					break
				}
			}
		}
		Write-Log "Local subnet $($localSubnet.Subnet): $($overlapping.Count) overlapping rule(s)." "DEBUG"
		if ($overlapping.Count -gt 0) {
			$overlapFound = $true
			$appIds = $overlapping | ForEach-Object { if ($_.appAuthorizationTokenContext.audienceScope -match 'api://([^/]+)') { $Matches[1] } } | Sort-Object -Unique
			Write-Log "Local subnet $($localSubnet.Subnet) overlaps $($overlapping.Count) Private Access IP rule(s) (App ID(s): $($appIds -join ', ')). With 'Prefer Local Network' on, matching traffic stays local and those corporate destinations are not reachable through Private Access from this network." "WARNING"
		}
	}
	if ($unparsedRanges -gt 0) {
		Write-Log "Could not interpret $unparsedRanges Private Access IP range(s) in the forwarding profile, so the overlap check may be incomplete." "WARNING"
	}
	if ($overlapFound) {
		Write-Log "Recommended action: Enable 'Prefer Local Network' only for users who need local resources, avoid publishing application segments that overlap home subnets, or publish corporate apps by FQDN / with more specific segments. To reach an overlapping corporate resource, turn 'Prefer Local Network' off in the client." "WARNING"
	}
	elseif ($unparsedRanges -eq 0) {
		Write-Log "No Private Access IP rule overlaps the directly connected local subnet(s)." "SUCCESS"
	}

	Write-Log "Test passed: Home network support is enabled." "SUCCESS"
	if ($PassThru)
	{ return $true }
}

#
# Function: Test-GSAEdgeDiagnosticsStatus
# Reads the GSA client's own cached per-channel health-check result from
# HKLM:\SOFTWARE\Microsoft\Global Secure Access Client\State\EdsResults - a pipe-delimited string
# the client keeps continuously up to date from its internal edge-diagnostics probes (the same
# auth/m365/private/internet.edgediagnostic.globalsecureaccess.microsoft.com checks surfaced by the
# Advanced Diagnostics tool and the tray icon). Confirmed via Process Monitor: both
# GlobalSecureAccessClient.exe and GlobalSecureAccessClientManagerService.exe read/write this value,
# e.g. "2026-11-15T19:34:32Z|User|Entra:0|M365:0|Private:0|Internet:0" (code 0 = healthy).
#
function Test-GSAEdgeDiagnosticsStatus {
	<#
.SYNOPSIS
	Reports the GSA client's own cached per-channel edge-diagnostics health status.
.DESCRIPTION
	Reads HKLM:\SOFTWARE\Microsoft\Global Secure Access Client\State\EdsResults, a pipe-delimited
	string of the form '<UTC timestamp>|<SessionContext>|Entra:<code>|M365:<code>|Private:<code>|Internet:<code>'
	that the GSA client keeps continuously up to date from its own internal edge-diagnostics probes
	(the same checks the Advanced Diagnostics tool and tray icon surface). A channel code of 0 means
	the client itself considers that channel healthy; any other value means the client has flagged
	that channel unhealthy. This is a fast, local/offline check (registry only) that complements the
	toolkit's own active connectivity probes (e.g. Test-GSADiagnosticUriConnectivity) by reporting
	what the client's always-running background health-check loop has already determined.
	A stale timestamp (older than -StaleAfterMinutes) suggests that background loop may be stalled.
.PARAMETER StaleAfterMinutes
	Age, in minutes, after which the cached EdsResults timestamp is flagged as stale. Default 15.
.PARAMETER PassThru
	Return the $true/$false test result. By default nothing is returned - only logged.
.PARAMETER LogLevel
	Sets the minimum log level written by the module. Valid values are ERROR, WARNING, INFO, DEBUG, and SUCCESS.
.OUTPUTS
	System.Boolean when -PassThru is specified. No output is returned by default.
.EXAMPLE
	Test-GSAEdgeDiagnosticsStatus
.EXAMPLE
	Test-GSAEdgeDiagnosticsStatus -StaleAfterMinutes 30 -PassThru
#>
	[CmdletBinding()]
	param (
		[int]$StaleAfterMinutes = 15,
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
	{ $script:LogLevel = $LogLevel }

	$registryPath = Join-Path -Path $script:GSAFwdProfileRegistryPath -ChildPath "State"
	$valueName = "EdsResults"

	Write-Log "Checking the GSA client's cached edge-diagnostics channel status (EdsResults)..." "INFO"

	$raw = Get-ItemPropertyValue -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
	if ([string]::IsNullOrWhiteSpace($raw)) {
		Write-Log "EdsResults registry value was not found. The client may not have completed an edge-diagnostics cycle yet, or this is an older client version that doesn't record this state." "WARNING"
		if ($PassThru)
		{ return $false }
		return
	}

	# Format: <UTC timestamp>|<SessionContext>|Entra:<code>|M365:<code>|Private:<code>|Internet:<code>
	$parts = @($raw -split '\|')
	if ($parts.Count -lt 3) {
		Write-Log "EdsResults value '$raw' is not in the expected pipe-delimited format. Skipping detailed parsing." "WARNING"
		if ($PassThru)
		{ return $false }
		return
	}

	$timestampRaw = $parts[0]
	$sessionContext = $parts[1]
	$channelParts = $parts[2..($parts.Count - 1)]

	$allHealthy = $true
	foreach ($channelPart in $channelParts) {
		if ($channelPart -notmatch '^(?<name>[^:]+):(?<code>-?\d+)$') {
			Write-Log "  Could not parse channel entry '$channelPart'." "DEBUG"
			continue
		}
		$name = $Matches.name
		$code = $Matches.code
		if ($code -eq '0') {
			Write-Log "  Channel '$name': healthy (code 0)." "SUCCESS"
		}
		else {
			Write-Log "  Channel '$name': reported unhealthy by the GSA client itself (code $code)." "ERROR"
			$allHealthy = $false
		}
	}

	try {
		$timestamp = [datetime]::Parse($timestampRaw, [System.Globalization.CultureInfo]::InvariantCulture,
			[System.Globalization.DateTimeStyles]::RoundtripKind)
		$age = (Get-Date).ToUniversalTime() - $timestamp.ToUniversalTime()
		if ($age.TotalMinutes -gt $StaleAfterMinutes) {
			Write-Log "EdsResults was last updated $([int]$age.TotalMinutes) minute(s) ago (UTC: $($timestamp.ToString('u')), session context: $sessionContext) - older than $StaleAfterMinutes minute(s). The client's background health-check loop may be stalled." "WARNING"
		}
		else {
			Write-Log "EdsResults was last updated $([int]$age.TotalMinutes) minute(s) ago (session context: $sessionContext)." "INFO"
		}
	}
	catch {
		Write-Log "Could not parse EdsResults timestamp '$timestampRaw': $($_.Exception.Message)" "DEBUG"
	}

	if (-not $allHealthy) {
		Write-Log "Recommended action: one or more GSA forwarding-profile channels are reported unhealthy by the client's own edge diagnostics. Open Advanced Diagnostics > Health check in the GSA client tray icon, and verify connectivity to the matching *.edgediagnostic.globalsecureaccess.microsoft.com endpoint." "WARNING"
		if ($PassThru)
		{ return $false }
		return
	}

	Write-Log "All GSA forwarding-profile channels are reported healthy by the client's own edge diagnostics." "SUCCESS"
	if ($PassThru)
	{ return $true }
}

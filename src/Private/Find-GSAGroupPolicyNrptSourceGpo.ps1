#
# Function: Find-GSAGroupPolicyNrptSourceGpo
# Helper for Test-GSAGroupPolicyNrptConflict -FindSourceGpo. Auto-detects the domain's SYSVOL
# Policies path, lets the user confirm/override it, then searches registry.pol files under it
# for 'dnspolicyconfig' to help locate the GPO(s) applying conflicting NRPT rules.
#
function Find-GSAGroupPolicyNrptSourceGpo {
	$searchString = "dnspolicyconfig"
	$fileName = "registry.pol"

	# Try to auto-detect this device's domain so a candidate SYSVOL path can be suggested.
	$detectedDomain = $null
	try {
		$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
		if ($computerSystem.PartOfDomain)
		{ $detectedDomain = $computerSystem.Domain }
	}
	catch {
		Write-Log "Could not determine domain membership via Win32_ComputerSystem: $($_.Exception.Message)" "DEBUG"
	}
	if (-not $detectedDomain -and $env:USERDNSDOMAIN)
	{ $detectedDomain = $env:USERDNSDOMAIN }

	if ($detectedDomain) {
		# \\<domain>\SYSVOL is a DFS namespace published by every domain controller, so this works
		# without needing to find/specify a particular DC.
		$candidateSysvolPath = "\\$detectedDomain\SYSVOL\$detectedDomain\Policies"
		Write-Log "Auto-detected SYSVOL Policies path: $candidateSysvolPath" "INFO"
		$response = Read-Host -Prompt "Press Enter to use this path, or type a different SYSVOL Policies path (e.g. \\dc1.contoso.com\sysvol\contoso.com\Policies)"
		$sysvolPath = if ([string]::IsNullOrWhiteSpace($response)) { $candidateSysvolPath } else { $response.Trim() }
	}
	else {
		Write-Log "Could not auto-detect this device's domain SYSVOL path (device may not be domain-joined)." "WARNING"
		$sysvolPath = Read-Host -Prompt "Enter the SYSVOL Policies path to search (e.g. \\dc1.contoso.com\sysvol\contoso.com\Policies), or leave blank to skip this step"
	}

	if ([string]::IsNullOrWhiteSpace($sysvolPath)) {
		Write-Log "Skipping SYSVOL GPO search." "INFO"
		return
	}

	Write-Log "Searching for GPOs with NRPT configuration under '$sysvolPath' (this may take a while)..." "INFO"

	try {
		$files = @(Get-ChildItem -Path $sysvolPath -Recurse -Filter $fileName -File -ErrorAction Stop)
	}
	catch {
		Write-Log "Failed to search '$sysvolPath' for '$fileName' files: $($_.Exception.Message)" "ERROR"
		return
	}

	$matchingFiles = @()
	foreach ($file in $files) {
		try {
			$content = Get-Content -Path $file.FullName -Encoding Unicode -ErrorAction Stop
			if ($content -like "*$searchString*")
			{ $matchingFiles += $file.FullName }
		}
		catch {
			Write-Log "Failed to read '$($file.FullName)': $($_.Exception.Message)" "WARNING"
		}
	}

	if ($matchingFiles.Count -eq 0) {
		Write-Log "No '$fileName' files referencing '$searchString' were found under '$sysvolPath'." "INFO"
	}
	else {
		Write-Log "Found $($matchingFiles.Count) GPO(s) with NRPT configuration (each path's GUID folder identifies the GPO):" "WARNING"
		foreach ($match in $matchingFiles)
		{ Write-Log "  - $match" "WARNING" -NoPrefix }
	}
}

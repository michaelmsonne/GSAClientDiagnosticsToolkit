#
# Function: Repair-GSAAuthCertificate
# Public function for the GSA client diagnostics toolkit.
#
function Repair-GSAAuthCertificate {
	<#
.SYNOPSIS
	Backs up and removes the GSA mTLS authentication certificate so the client re-enrolls a new one.
.DESCRIPTION
	Implements the remediation steps documented for the GSA client's "Authentication certificate
	exists"/"Authentication certificate is valid" Health check tests:
		1. Locates certificate(s) with a subject ending in 'gsa.client' in the LocalMachine\My store.
		2. Backs up each certificate BEFORE touching anything - as a password-protected .pfx (with the
		   private key) when exportable, otherwise falls back to a public-key-only .cer file.
		3. Requires TWO separate explicit confirmations before deleting a certificate: the standard
		   -WhatIf/-Confirm prompt, plus a second prompt requiring you to type the certificate's
		   thumbprint. This is a destructive, hard-to-reverse action.
		4. Deletes the certificate and clears the CertCommonName registry value so the GSA Engine
		   service re-provisions a new certificate.
	A new certificate is only issued after the GlobalSecureAccessEngineService is restarted (pass
	-RestartEngineService to do this automatically); provisioning can take a few minutes.
.PARAMETER BackupPath
	Directory to export the certificate backup(s) to before deletion. Defaults to the current directory.
.PARAMETER RestartEngineService
	Restart the GlobalSecureAccessEngineService after removing the certificate, so a new one is
	provisioned immediately instead of on its next natural cycle.
.PARAMETER PassThru
	Return the $true/$false result. By default nothing is returned - only logged.
.PARAMETER LogLevel
	Sets the minimum log level written by the module. Valid values are ERROR, WARNING, INFO, DEBUG, and SUCCESS.
.OUTPUTS
	System.Boolean when -PassThru is specified. No output is returned by default.
.EXAMPLE
	Repair-GSAAuthCertificate -BackupPath C:\Temp\GSACertBackup -RestartEngineService
#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
	param (
		[string]$BackupPath = (Get-Location).Path,
		[switch]$RestartEngineService,
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
	{ $script:LogLevel = $LogLevel }

	if (-not (Test-IsElevated)) {
		Write-Log "This function must be run elevated (as Administrator) to access the LocalMachine certificate store and registry." "ERROR"
		if ($PassThru)
		{ return $false }
		return
	}

	$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', 'LocalMachine')
	try {
		$store.Open('ReadOnly')
		$certs = @($store.Certificates | Where-Object { $_.Subject -match 'gsa\.client$' })
	}
	catch {
		Write-Log "Failed to read the LocalMachine\My certificate store: $($_.Exception.Message)" "ERROR"
		if ($PassThru)
		{ return $false }
		return
	}
	finally {
		$store.Close()
	}

	if ($certs.Count -eq 0) {
		Write-Log "No GSA authentication certificate was found - nothing to repair." "WARNING"
		if ($PassThru)
		{ return $false }
		return
	}

	if (-not (Test-Path $BackupPath)) {
		if ($PSCmdlet.ShouldProcess($BackupPath, 'Create backup directory')) {
			New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
		}
	}

	Write-Log "Backing up the certificate(s) before making any changes..." "INFO"
	$exportedFiles = @(Export-GSAAuthCertificate -BackupPath $BackupPath -PassThru -WhatIf:$WhatIfPreference -Confirm:$false)

	$allSucceeded = $true

	foreach ($cert in $certs) {
		Write-Log "Found GSA authentication certificate '$($cert.Subject)' (Thumbprint: $($cert.Thumbprint))." "INFO"

		# Always back up the certificate before touching anything (skip this gate under -WhatIf,
		# since the backup step above is itself only previewed, not actually performed)
		$backupFile = @($exportedFiles) | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) -eq $cert.Thumbprint } | Select-Object -First 1

		if (-not $backupFile -and -not $WhatIfPreference) {
			Write-Log "Skipping deletion of '$($cert.Thumbprint)' because a backup could not be created." "ERROR"
			$allSucceeded = $false
			continue
		}

		# First confirmation: standard -WhatIf/-Confirm support
		if (-not $PSCmdlet.ShouldProcess("Certificate '$($cert.Subject)' (Thumbprint: $($cert.Thumbprint))", "Delete from LocalMachine\My")) {
			Write-Log "Deletion of '$($cert.Thumbprint)' was skipped (not confirmed)." "WARNING"
			$allSucceeded = $false
			continue
		}

		# Second, explicit confirmation - deliberately separate from -Confirm so -Confirm:$false cannot bypass it
		$confirmation = Read-Host -Prompt "Type the certificate thumbprint '$($cert.Thumbprint)' to confirm PERMANENT deletion (backup saved to $backupFile)"
		if ($confirmation -ne $cert.Thumbprint) {
			Write-Log "Deletion of '$($cert.Thumbprint)' was NOT confirmed (input did not match the thumbprint). Skipping." "WARNING"
			$allSucceeded = $false
			continue
		}

		try {
			Remove-Item -Path "Cert:\LocalMachine\My\$($cert.Thumbprint)" -Force -ErrorAction Stop
			Write-Log "Deleted certificate '$($cert.Thumbprint)' from LocalMachine\My." "SUCCESS"
		}
		catch {
			Write-Log "Failed to delete certificate '$($cert.Thumbprint)': $($_.Exception.Message)" "ERROR"
			$allSucceeded = $false
			continue
		}
	}

	Write-Log "Clearing the CertCommonName registry value so the GSA client re-enrolls a new certificate..." "INFO"
	if ($PSCmdlet.ShouldProcess("$script:GSAFwdProfileRegistryPath\CertCommonName", "Remove registry value")) {
		try {
			Remove-ItemProperty -Path $script:GSAFwdProfileRegistryPath -Name "CertCommonName" -ErrorAction Stop
			Write-Log "Removed the CertCommonName registry value." "SUCCESS"
		}
		catch {
			Write-Log "CertCommonName registry value was not found or could not be removed (it may already be absent): $($_.Exception.Message)" "WARNING"
		}
	}

	if ($RestartEngineService) {
		if ($PSCmdlet.ShouldProcess("GlobalSecureAccessEngineService", "Restart")) {
			try {
				Restart-Service -Name "GlobalSecureAccessEngineService" -Force -ErrorAction Stop
				Write-Log "Restarted GlobalSecureAccessEngineService. A new certificate should be provisioned within a few minutes." "SUCCESS"
			}
			catch {
				Write-Log "Failed to restart GlobalSecureAccessEngineService: $($_.Exception.Message)" "ERROR"
				$allSucceeded = $false
			}
		}
	}
	else {
		Write-Log "Recommended action: Restart the 'GlobalSecureAccessEngineService' service (or re-run with -RestartEngineService) so a new certificate is provisioned." "WARNING"
	}

	if ($PassThru)
	{ return $allSucceeded }
}

#
# Function: Export-GSAAuthCertificate
# Public function for the GSA client diagnostics toolkit.
#
function Export-GSAAuthCertificate
{
	<#
.SYNOPSIS
	Exports (backs up) the GSA mTLS authentication certificate(s) without modifying or deleting them.
.DESCRIPTION
	Locates certificate(s) with a subject ending in 'gsa.client' in the LocalMachine\My store and
	exports each one to -BackupPath: as a password-protected .pfx (including the private key) when
	the key is exportable, otherwise falls back to a public-key-only .cer file. This is a read-only,
	non-destructive operation - use it to create a backup before running Repair-GSAAuthCertificate,
	or simply to archive the current certificate.
.PARAMETER BackupPath
	Directory to export the certificate backup(s) to. Defaults to the current directory.
.PARAMETER PassThru
	Return the exported file path(s). By default nothing is returned - only logged.
.PARAMETER LogLevel
	Sets the minimum log level written by the module. Valid values are ERROR, WARNING, INFO, DEBUG, and SUCCESS.
.OUTPUTS
	System.String[] when -PassThru is specified. No output is returned by default.
.EXAMPLE
	Export-GSAAuthCertificate -BackupPath C:\Temp\GSACertBackup
.EXAMPLE
	Export-GSAAuthCertificate -BackupPath C:\Temp\GSACertBackup -PassThru
	Exports the certificates and returns the paths of the files that were created.
#>
	[CmdletBinding(SupportsShouldProcess)]
	param (
		[string]$BackupPath = (Get-Location).Path,
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

		if ($PSBoundParameters.ContainsKey('LogLevel'))
		{
		$script:LogLevel = $LogLevel
	}

		if (-not (Test-IsElevated))
		{
		Write-Log "This function must be run elevated (as Administrator) to access the LocalMachine certificate store." "ERROR"
		return
	}

		if (Test-Path -LiteralPath $BackupPath -PathType Leaf)
		{
		Write-Log "BackupPath points to a file, not a directory: $BackupPath" "ERROR"
		return
	}

	$store = $null

	# Open the LocalMachine\My certificate store and locate GSA authentication certificates.
	try
	{
		$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', 'LocalMachine')
		$store.Open('ReadOnly')
		$certs = @($store.Certificates | Where-Object { $_.Subject -match 'gsa\.client$' })
	}
	catch
	{
		Write-Log "Failed to read the LocalMachine\My certificate store: $($_.Exception.Message)" "ERROR"
		return
	}
	finally
	{
		if ($null -ne $store)
		{
			$store.Close()
		}
	}

	# Check if any GSA authentication certificates were found and handle the case where none are present.
	if ($certs.Count -eq 0)
	{
		Write-Log "No GSA authentication certificate was found - nothing to export." "WARNING"
		return
	}

	# Ensure the backup directory exists, creating it if necessary.
	if (-not (Test-Path $BackupPath))
	{
		if ($PSCmdlet.ShouldProcess($BackupPath, 'Create backup directory'))
		{
			try
			{
				New-Item -ItemType Directory -Path $BackupPath -Force -ErrorAction Stop | Out-Null
			}
			catch
			{
				Write-Log "Failed to create backup directory '$BackupPath': $($_.Exception.Message)" "ERROR"
				return
			}
		}
	}

	# Initialize a list to keep track of the exported certificate files.
	$exportedFiles = [System.Collections.Generic.List[string]]::new()

	# Iterate over each GSA authentication certificate and attempt to export it.
	foreach ($cert in $certs)
	{
		Write-Log "Found GSA authentication certificate '$($cert.Subject)' (Thumbprint: $($cert.Thumbprint))." "INFO"

		$exported = $false
		$backupFile = Join-Path -Path $BackupPath -ChildPath "$($cert.Thumbprint).pfx"
		# Prefer a protected PFX, but retain a public certificate backup when the private key is not exportable.
		if ($cert.HasPrivateKey -and $PSCmdlet.ShouldProcess("$($cert.Thumbprint) (with private key)", "Export to $backupFile"))
		{
			try
			{
				$backupPassword = Read-Host -Prompt "Enter a password to protect the certificate backup ($backupFile)" -AsSecureString
				Export-PfxCertificate -Cert $cert -FilePath $backupFile -Password $backupPassword -ErrorAction Stop | Out-Null
				Write-Log "Exported certificate (with private key) to: $backupFile" "SUCCESS"
				$exported = $true
			}
			catch
			{
				Write-Log "Could not export the certificate with its private key: $($_.Exception.Message)" "WARNING"
				Write-Log "If the key is exportable, you can also export it manually: certlm.msc > Personal > Certificates > right-click the '$($cert.Thumbprint)' certificate > All Tasks > Export > Yes, export the private key." "WARNING"
			}
		}

		# If the certificate was not exported with its private key, attempt to export the public certificate.
		if (-not $exported)
		{
			$backupFile = Join-Path -Path $BackupPath -ChildPath "$($cert.Thumbprint).cer"
			if ($PSCmdlet.ShouldProcess($cert.Thumbprint, "Export public certificate to $backupFile"))
			{
				try
				{
					Export-Certificate -Cert $cert -FilePath $backupFile -ErrorAction Stop | Out-Null
					Write-Log "Exported the public certificate (no private key) to: $backupFile" "SUCCESS"
					$exported = $true
				}
				catch
				{
					Write-Log "Failed to export the certificate: $($_.Exception.Message)" "ERROR"
					Write-Log "You can export it manually instead: certlm.msc > Personal > Certificates > right-click the '$($cert.Thumbprint)' certificate > All Tasks > Export." "WARNING"
				}
			}
		}

		# If the certificate was successfully exported, add it to the list of exported files.
		if ($exported)
		{
			[void]$exportedFiles.Add($backupFile)
		}
	}

	if ($PassThru)
	{
		return $exportedFiles
	}
}

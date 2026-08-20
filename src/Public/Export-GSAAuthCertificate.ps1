function Export-GSAAuthCertificate {
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
.EXAMPLE
    Export-GSAAuthCertificate -BackupPath C:\Temp\GSACertBackup
#>
    [CmdletBinding()]
    param (
        [string]$BackupPath = (Get-Location),
        [switch]$PassThru,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    if (-not (Test-IsElevated)) {
        Write-Log "This function must be run elevated (as Administrator) to access the LocalMachine certificate store." "ERROR"
        return
    }

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', 'LocalMachine')
    try {
        $store.Open('ReadOnly')
        $certs = @($store.Certificates | Where-Object { $_.Subject -match 'gsa\.client' })
    }
    catch {
        Write-Log "Failed to read the LocalMachine\My certificate store: $_" "ERROR"
        return
    }
    finally {
        $store.Close()
    }

    if ($certs.Count -eq 0) {
        Write-Log "No GSA authentication certificate was found - nothing to export." "WARNING"
        return
    }

    if (-not (Test-Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    }

    $exportedFiles = @()

    foreach ($cert in $certs) {
        Write-Log "Found GSA authentication certificate '$($cert.Subject)' (Thumbprint: $($cert.Thumbprint))." "INFO"

        $exported = $false
        $backupFile = Join-Path -Path $BackupPath -ChildPath "$($cert.Thumbprint).pfx"
        if ($cert.HasPrivateKey) {
            try {
                $backupPassword = Read-Host -Prompt "Enter a password to protect the certificate backup ($backupFile)" -AsSecureString
                Export-PfxCertificate -Cert $cert -FilePath $backupFile -Password $backupPassword -ErrorAction Stop | Out-Null
                Write-Log "Exported certificate (with private key) to: $backupFile" "SUCCESS"
                $exported = $true
            }
            catch {
                Write-Log "Could not export the certificate with its private key: $_" "WARNING"
                Write-Log "If the key is exportable, you can also export it manually: certlm.msc > Personal > Certificates > right-click the '$($cert.Thumbprint)' certificate > All Tasks > Export > Yes, export the private key." "WARNING"
            }
        }

        if (-not $exported) {
            $backupFile = Join-Path -Path $BackupPath -ChildPath "$($cert.Thumbprint).cer"
            try {
                Export-Certificate -Cert $cert -FilePath $backupFile -ErrorAction Stop | Out-Null
                Write-Log "Exported the public certificate (no private key) to: $backupFile" "SUCCESS"
                $exported = $true
            }
            catch {
                Write-Log "Failed to export the certificate: $_" "ERROR"
                Write-Log "You can export it manually instead: certlm.msc > Personal > Certificates > right-click the '$($cert.Thumbprint)' certificate > All Tasks > Export." "WARNING"
            }
        }

        if ($exported) { $exportedFiles += $backupFile }
    }

    if ($PassThru) { return $exportedFiles }
}

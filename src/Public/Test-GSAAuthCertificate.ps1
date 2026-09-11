#
# Function: Test-GSAAuthCertificate
# Public function for the GSA client diagnostics toolkit.
#
function Test-GSAAuthCertificate {
    <#
.SYNOPSIS
    Checks whether a valid GSA mTLS authentication certificate exists on the device.
.DESCRIPTION
    Mirrors the "Authentication certificate exists" / "Authentication certificate is valid" tests
    from the GSA client's built-in Advanced Diagnostics Health check: looks for a certificate whose
    subject ends in 'gsa.client' in the LocalMachine\My store and verifies it has a private key and
    hasn't expired. This test only applies to tenants with mTLS enabled for Global Secure Access - if
    mTLS isn't enabled, no certificate is expected to exist.
.PARAMETER PassThru
    Return the $true/$false test result. By default nothing is returned - only logged.
.EXAMPLE
    Test-GSAAuthCertificate
#>
    [CmdletBinding()]
    param (
        [switch]$PassThru,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    Write-Log "Checking for a GSA mTLS authentication certificate (subject ending in 'gsa.client')..." "INFO"

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', 'LocalMachine')
    try {
        $store.Open('ReadOnly')
        $certs = @($store.Certificates | Where-Object { $_.Subject -match 'gsa\.client$' })
    }
    catch {
        Write-Log "Failed to read the LocalMachine\My certificate store: $($_.Exception.Message)" "ERROR"
        if ($PassThru) { return $false }
        return
    }
    finally {
        $store.Close()
    }

    if ($certs.Count -eq 0) {
        Write-Log "No GSA authentication certificate was found in the LocalMachine\My certificate store." "WARNING"
        Write-Log "Recommended action: This is expected if mTLS isn't enabled for your tenant. If mTLS IS enabled, use Repair-GSAAuthCertificate to force the client to re-enroll a certificate." "WARNING"
        if ($PassThru) { return $false }
        return
    }

    $allValid = $true
    foreach ($cert in $certs) {
        if (-not $cert.HasPrivateKey) {
            Write-Log "Certificate '$($cert.Subject)' (Thumbprint: $($cert.Thumbprint)) has no private key." "ERROR"
            $allValid = $false
            continue
        }
        if ($cert.NotAfter -le (Get-Date)) {
            Write-Log "Certificate '$($cert.Subject)' (Thumbprint: $($cert.Thumbprint)) expired on $($cert.NotAfter)." "ERROR"
            $allValid = $false
            continue
        }
        Write-Log "Certificate '$($cert.Subject)' (Thumbprint: $($cert.Thumbprint)) is present and valid until $($cert.NotAfter)." "SUCCESS"
    }

    if (-not $allValid) {
        Write-Log "Recommended action: Use Repair-GSAAuthCertificate to back up and remove the invalid/expired certificate so the GSA client can re-enroll a new one." "WARNING"
        if ($PassThru) { return $false }
        return
    }

    if ($PassThru) { return $true }
}

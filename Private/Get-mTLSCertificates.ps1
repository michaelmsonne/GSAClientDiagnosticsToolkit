function Get-mTLSCertificates {
    param (
        [string]$StoreName     = "My",
        [string]$StoreLocation = "LocalMachine"
    )

    $mtlsCerts = @()
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, $StoreLocation)

    try {
        $store.Open("ReadOnly")
        $certs = $store.Certificates | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) }

        foreach ($cert in $certs) {
            try {
                $ekuExtensions   = $cert.Extensions | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] }
                $clientAuthFound = $false

                foreach ($extension in $ekuExtensions) {
                    foreach ($usage in $extension.EnhancedKeyUsages) {
                        if ($usage.Value -eq "1.3.6.1.5.5.7.3.2") {
                            $clientAuthFound = $true
                            break
                        }
                    }
                    if ($clientAuthFound) { break }
                }

                if ($clientAuthFound -and $cert.Subject -match "tenant.gsa.client") {
                    $mtlsCerts += $cert
                    Write-Log "Certificate accepted for mTLS: Subject=$($cert.Subject), Thumbprint=$($cert.Thumbprint) and with the GSA specific Subject name" "SUCCESS"
                }
            }
            catch {
                Write-Log "Error processing certificate $($cert.Subject): $_" "ERROR"
            }
        }
        return $mtlsCerts
    }
    catch {
        Write-Log "Error retrieving certificates from store: $_" "ERROR"
        return @()
    }
    finally {
        $store.Close()
    }
}

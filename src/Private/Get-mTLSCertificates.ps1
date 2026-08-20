# 
# Function: Get-mTLSCertificates enumarates 
# the certificates in the LocalMachine "My" store
# 
function Get-mTLSCertificates {
    param (
        [string]$StoreName = "My",
        [string]$StoreLocation = "LocalMachine"
    )

    $mtlsCerts = @()
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, $StoreLocation)

    try {
        $store.Open("ReadOnly")
        # Filter certificates that have a private key and are not expired
        $certs = $store.Certificates | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) }

        foreach ($cert in $certs) {
            try {
                # Get all EKU extensions for the certificate
                $ekuExtensions = $cert.Extensions | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] }
                $clientAuthFound = $false

                foreach ($extension in $ekuExtensions) {
                    # look for Client Auth certs only ...
                    foreach ($usage in $extension.EnhancedKeyUsages) {
                        if ($usage.Value -eq "1.3.6.1.5.5.7.3.2") {
                            $clientAuthFound = $true
                            break
                        }
                    }
                    if ($clientAuthFound) { break }
                }

                if ($clientAuthFound -and $cert.Subject -match "tenant.gsa.client") {
                    # we found a capable mTLS certificate - only add certs with tenant.gsa.client in the subject
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

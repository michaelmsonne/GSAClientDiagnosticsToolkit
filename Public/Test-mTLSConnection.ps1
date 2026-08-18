function Test-mTLSConnection {
<#
.SYNOPSIS
    Tests mTLS connectivity to a list of FQDNs using GSA client certificates.
.PARAMETER fqdnList
    List of FQDNs to test.
.PARAMETER port
    TCP port to connect on (default: 443).
#>
    param (
        [string[]]$fqdnList,
        [int]$port = 443
    )

    $allTestsPassed  = $true
    $warningsLogged  = $false
    $runningElevated = Test-IsElevated

    if (-not $runningElevated) {
        Write-Log "This script is not running elevated" "WARNING"
        Write-Log "mTLS checks will most likely fail, due to missing permissions on the computer's mTLS certificate private key(s)" "WARNING"
        $warningsLogged = $true
    }

    $mtlsCertificates = Get-mTLSCertificates

    if ($mtlsCertificates.Count -eq 0) {
        Write-Log "No mTLS-capable certificates were found." "WARNING"
        Write-Log "This could be normal, if the tenant is not yet onboarded to mTLS" "WARNING"
        Write-Log "Skipping mTLS connection attempts due to lack of mTLS-capable certificates." "INFO"
        return [PSCustomObject]@{
            Passed   = $true
            Warnings = 1
        }
    } else {
        Write-Log "Found $($mtlsCertificates.Count) mTLS-capable GSA client certificate(s)." "SUCCESS"
    }

    foreach ($fqdn in $fqdnList) {
        Write-Log "Attempting mTLS connection to: $fqdn on port $port" "INFO"

        foreach ($ClientCert in $mtlsCertificates) {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            try {
                $tcpClient.Connect($fqdn, $port)
                Write-Log "TCP connection successful to $fqdn" "SUCCESS"
            }
            catch {
                Write-Log "TCP connection failed to $fqdn : $_" "ERROR"
                $allTestsPassed = $false
                continue
            }

            $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, ({ $true }))
            try {
                $clientCerts = New-Object System.Security.Cryptography.X509Certificates.X509CertificateCollection
                if ($ClientCert) { [void]$clientCerts.Add($ClientCert) }

                $sslStream.AuthenticateAsClient($fqdn, $clientCerts, [System.Security.Authentication.SslProtocols]::Tls12, $false)
                $ismTLSdone = $sslStream.Ismutuallyauthenticated
                Write-Log "mTLS handshake succeeded for $fqdn with certificate $($ClientCert.Subject) mTLS: $ismTLSdone" "SUCCESS"
            }
            catch {
                if (-not $runningElevated) {
                    Write-Log "mTLS handshake failed for $fqdn " "WARNING"
                    Write-Log "Expected due to not running elevated. Run again with elevation" "WARNING"
                    $warningsLogged = $true
                } else {
                    Write-Log "mTLS handshake failed for $fqdn with certificate $($ClientCert.Subject) : $_" "ERROR"
                    $allTestsPassed = $false
                }
            }
            finally {
                $sslStream.Dispose()
                $tcpClient.Close()
            }
        }
    }

    if (-not $allTestsPassed) {
        Write-Log "One or more mTLS connection attempts failed." "WARNING"
        $warningsLogged = $true
    }

    return [PSCustomObject]@{
        Passed   = $allTestsPassed
        Warnings = if ($warningsLogged) { 1 } else { 0 }
    }
}

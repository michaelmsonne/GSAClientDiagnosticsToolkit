#
# Function: Test-TLSConnection
# Public function for the GSA client diagnostics toolkit.
#
function Test-TLSConnection {
    <#
.SYNOPSIS
    Tests TLS connectivity to a list of FQDNs on the specified port.
.PARAMETER fqdnList
    List of FQDNs to test.
.PARAMETER port
    TCP port to connect on (default: 443).
#>
    [CmdletBinding()]
    param (
        [string[]]$fqdnList,
        [int]$port = 443,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    $allTestsPassed = $true

    foreach ($fqdn in $fqdnList) {
        Write-Log "Checking connection to: $fqdn on port $port" "INFO"

        try {
            # Create and connect the TCP client
            $tcpClient = [System.Net.Sockets.TcpClient]::new($fqdn, $port)
            Write-Log "TCP connection successful to $fqdn" "SUCCESS"

            # Create and authenticate the SSL stream
            $sslStream = [System.Net.Security.SslStream]::new($tcpClient.GetStream(), $false, { $true })
            try {
                $sslStream.AuthenticateAsClient($fqdn)
                Write-Log "TLS handshake successful with $fqdn" "SUCCESS"

                # Log certificate details if in DEBUG mode
                if ($script:LogLevel -eq "DEBUG") {
                    $remoteCertificate = $sslStream.RemoteCertificate
                    if ($remoteCertificate) {
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $remoteCertificate
                        Write-Log "TLS Certificate Details for $fqdn :" "DEBUG"
                        Write-Log "  Subject: $($cert.Subject)" "DEBUG"
                        Write-Log "  Issuer: $($cert.Issuer)" "DEBUG"
                        Write-Log "  Valid From: $($cert.NotBefore)" "DEBUG"
                        Write-Log "  Valid Until: $($cert.NotAfter)" "DEBUG"
                        Write-Log "  Thumbprint: $($cert.Thumbprint)" "DEBUG"
                    }
                    else {
                        Write-Log "No TLS certificate information available for $fqdn." "DEBUG"
                    }
                }
            }
            catch {
                Write-Log "TLS handshake failed with $fqdn : $($_.Exception.Message)" "ERROR"
                $allTestsPassed = $false
            }
            finally {
                $sslStream.Dispose()
            }
        }
        catch {
            Write-Log "TCP connection failed to $fqdn : $($_.Exception.Message)" "ERROR"
            $allTestsPassed = $false
        }
        finally {
            if ($tcpClient) { $tcpClient.Close() }
        }
    }

    return $allTestsPassed
}

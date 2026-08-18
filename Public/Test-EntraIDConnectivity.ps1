function Test-EntraIDConnectivity {
<#
.SYNOPSIS
    Tests TLS/HTTPS connectivity to core Entra ID endpoints.
.PARAMETER Endpoints
    List of Entra ID endpoint URLs to test.
.PARAMETER Timeout
    HTTP request timeout in seconds.
#>
    param (
        [string[]]$Endpoints = @(
            "https://login.microsoftonline.com",         # Microsoft Azure Worldwide
            "https://login.windows.net",                 # Token provider for Entra ID/Azure AD
            "https://login.microsoft.com",               # 
            "https://logincert.microsoftonline.com",     #
            "https://graph.microsoft.com",               # Microsoft Graph API
            "https://sts.windows.net",                   # Security Token Service
            "https://login.live.com",                    # Microsoft Account endpoint 
            "https://aadcdn.msauth.net",                 # CDN for loging prompt rendering              
            "https://aadcdn.msftauthimages.net",         # CDN for loging prompt rendering
            "https://enterpriseregistration.windows.net",# Device Registration endpoint
            "https://device.login.microsoftonline.com",  # Device Auth
            "https://certauth.login.microsoftonline.com" # CBA AuthN
        ),
        [int]$Timeout = 15
    )

    $allTestsPassed = $true

    foreach ($url in $Endpoints) {
        try {
            Write-Log -Message "Testing connectivity to $url ..." -Level "INFO"

            $uri       = [System.Uri]::new($url)
            $tcpClient = [System.Net.Sockets.TcpClient]::new($uri.Host, 443)
            $sslStream = [System.Net.Security.SslStream]::new($tcpClient.GetStream(), $false, { $true })
            try {
                $sslStream.AuthenticateAsClient($uri.Host)

                if ($script:LogLevel -eq "DEBUG") {
                    $remoteCertificate = $sslStream.RemoteCertificate
                    if ($remoteCertificate) {
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $remoteCertificate
                        Write-Log "TLS Certificate Details for $url :" "DEBUG"
                        Write-Log "  Subject: $($cert.Subject)" "DEBUG"
                        Write-Log "  Issuer: $($cert.Issuer)" "DEBUG"
                        Write-Log "  Valid From: $($cert.NotBefore)" "DEBUG"
                        Write-Log "  Valid Until: $($cert.NotAfter)" "DEBUG"
                        Write-Log "  Thumbprint: $($cert.Thumbprint)" "DEBUG"
                    } else {
                        Write-Log "No TLS certificate information available for $url." "DEBUG"
                    }
                }
            }
            finally {
                $sslStream.Dispose()
                $tcpClient.Close()
            }

            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $Timeout
            if ($response.StatusCode -eq 200) {
                Write-Log -Message "Successfully connected to $url" -Level "SUCCESS"
            }
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Response -and ($_.Exception.Response.StatusCode -ge 400 -and $_.Exception.Response.StatusCode -lt 500)) {
                Write-Log -Message "Successfully connected to '$url'. Received HTTP status code: $($_.Exception.Response.StatusCode) ($($_.Exception.Response.StatusDescription)). This is expected for some endpoints." -Level "WARNING"
            } else {
                Write-Log -Message "Failed to connect to $url - $($_.Exception.Message)" -Level "ERROR"
                $allTestsPassed = $false
            }
        }
        catch {
            Write-Log -Message "An unexpected error occurred while connecting to $url - $($_.Exception.Message)" -Level "ERROR"
            $allTestsPassed = $false
        }
    }
    return $allTestsPassed
}

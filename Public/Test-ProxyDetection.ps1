function Test-ProxyDetection {
<#
.SYNOPSIS
    Detects outbound proxy presence via system config, transparent proxy headers, and HTTP 407 responses.
.PARAMETER TestUrlHttp
    HTTP URL used for transparent proxy header detection.
.PARAMETER TestUrlHttps
    HTTPS URL used for authenticating proxy (407) detection.
.PARAMETER TimeoutSec
    Request timeout in seconds.
#>
    [CmdletBinding()]
    param (
        [string]$TestUrlHttp  = "http://www.msftconnecttest.com/connecttest.txt",
        [string]$TestUrlHttps = "https://www.microsoft.com",
        [int]$TimeoutSec      = 10,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    $result = [PSCustomObject]@{
        ProxyFound                  = $false
        SystemProxyConfigured       = $false
        ProxyAddress                = $null
        TransparentProxyDetected    = $false
        AuthenticatingProxyDetected = $false
        Passed                      = $true
        Warnings                    = 0
    }

    # Check system proxy via netsh
    try {
        $netshOutput = netsh winhttp show proxy 2>&1
        if ($netshOutput -match "Direct access") {
            $result.SystemProxyConfigured = $false
            Write-Log -Message "System proxy is not configured (Direct access mode)." -Level "INFO"
        } else {
            $result.SystemProxyConfigured = $true
            Write-Log -Message "System proxy is configured." -Level "INFO"
            if ($netshOutput -match "Proxy Server\s*:\s*(.+)") {
                $result.ProxyAddress = $matches[1].Trim()
                Write-Log -Message "Detected system proxy address: $($result.ProxyAddress)" -Level "WARNING"
                $result.ProxyFound = $true
                $result.Warnings++
            }
        }
    }
    catch {
        Write-Log -Message "Error retrieving system proxy settings: $_" -Level "ERROR"
        $result.Passed = $false
    }

    # Check gRPC proxy environment variable
    if (Test-grpcProxy) {
        Write-Log -Message "grpc_proxy variables are set." -Level "WARNING"
        $result.Warnings++
    } else {
        Write-Log -Message "NO grpc_proxy environment variables are set." -Level "INFO"
    }

    # Check WinHTTP/WebRequest proxy
    $proxy = Test-SystemWebProxy -TargetUrl 'http://www.microsoft.com'
    if ($proxy) {
        Write-Log -Message "SystemWebProxy: Found proxy: $proxy" -Level "WARNING"
        $result.ProxyFound = $true
        $result.Warnings++
    } else {
        Write-Log -Message "SystemWebProxy: Direct connection will be used." -Level "INFO"
    }

    # Transparent proxy detection via HTTP headers
    try {
        $responseHttp = Invoke-WebRequest -Uri $TestUrlHttp -UseBasicParsing -TimeoutSec $TimeoutSec
        Write-Log -Message "HTTP test request to $TestUrlHttp succeeded." -Level "INFO"

        if ($responseHttp.Headers["Via"] -or $responseHttp.Headers["X-Forwarded-For"]) {
            $result.TransparentProxyDetected = $true
            Write-Log -Message "Transparent proxy detected via HTTP header(s): $responseHttp.Headers" -Level "WARNING"
            $result.ProxyFound = $true
            $result.Warnings++
        }
    }
    catch {
        Write-Log -Message "HTTP test error: $_" -Level "ERROR"
        $result.Passed = $false
    }

    # Authenticating proxy detection via HTTP 407
    try {
        Invoke-WebRequest -Uri $TestUrlHttps -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop | Out-Null
        Write-Log -Message "HTTPS test request to $TestUrlHttps succeeded." -Level "INFO"
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 407) {
            $result.AuthenticatingProxyDetected = $true
            Write-Log -Message "Authenticating proxy detected (HTTP 407 response)." -Level "WARNING"
            $result.ProxyFound = $true
            $result.Warnings++
        } else {
            Write-Log -Message "HTTPS test error: $_" -Level "ERROR"
            $result.Passed = $false
        }
    }

    return $result
}

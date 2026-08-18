function Test-SystemWebProxy {
    param (
        [string]$TargetUrl = 'http://www.microsoft.com'
    )

    try {
        $uri      = New-Object System.Uri($TargetUrl)
        $webProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $proxyUri = $webProxy.GetProxy($uri)

        if ($proxyUri -ne $uri) {
            Write-Log -Message "Proxy detected for $TargetUrl : $proxyUri" -Level "WARNING"
            return $proxyUri
        } else {
            return $null
        }
    }
    catch {
        Write-Log -Message "Error during proxy detection: $_" -Level "ERROR"
        return $null
    }
}

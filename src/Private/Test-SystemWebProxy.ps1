#
# Function: Test-SystemWebProxy
# checks system webproxy configuration using GetProxy
#
function Test-SystemWebProxy
{
	param (
		[string]$TargetUrl = 'http://www.microsoft.com'
	)

	try
    {
		# Create a Uri object from the target URL
		$uri = New-Object System.Uri($TargetUrl)
		# Get the system's default proxy instance
		$webProxy = [System.Net.WebRequest]::GetSystemWebProxy()
		# Get the proxy URI for the target URL
		$proxyUri = $webProxy.GetProxy($uri)

		# Determine if a proxy is being used
		if ($proxyUri -ne $uri)
        {
			Write-Log -Message "Proxy detected for $TargetUrl : $proxyUri" -Level "WARNING"
			return $proxyUri
		}
		else
        {
			return $null
		}
	}
	catch
    {
		Write-Log -Message "Error during proxy detection: $($_.Exception.Message)" -Level "ERROR"
		return $null
	}
}

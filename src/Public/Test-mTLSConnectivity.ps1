#
# Function: Test-mTLSConnectivity
# Public function for the GSA client diagnostics toolkit.
#
function Test-mTLSConnectivity
{
	<#
.SYNOPSIS
	Tests mTLS connectivity to a list of FQDNs using GSA client certificates.
.PARAMETER fqdnList
	List of FQDNs to test.
.PARAMETER port
	TCP port to connect on (default: 443).
.PARAMETER PassThru
	Returns the test result object. By default the result is only logged.
.PARAMETER LogLevel
	Sets the minimum log level written by the module. Valid values are ERROR, WARNING, INFO, DEBUG, and SUCCESS.
.OUTPUTS
	PSCustomObject when -PassThru is specified. The object contains Passed and Warnings properties.
#>
	[CmdletBinding()]
	param (
		[string[]]$fqdnList,
		[int]$port = 443,
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	# Initialize test result tracking variables.
	$allTestsPassed = $true
	$warningsLogged = $false
	$runningElevated = Test-IsElevated

	# Check if the script is running with elevated privileges.
	if (-not $runningElevated)
    {
		Write-Log "This script is not running elevated" "WARNING"
		Write-Log "mTLS checks will most likely fail, due to missing permissions on the computer's mTLS certificate private key(s)" "WARNING"
		$warningsLogged = $true
	}

	# Retrieve mTLS-capable certificates from the LocalMachine "My" store.
	$mtlsCertificates = Get-mTLSCertificates

	if ($mtlsCertificates.Count -eq 0)
    {
		Write-Log "No mTLS-capable certificates were found." "WARNING"
		Write-Log "This could be normal, if the tenant is not yet onboarded to mTLS" "WARNING"
		# Skip the test since no certificates are available
		Write-Log "Skipping mTLS connection attempts due to lack of mTLS-capable certificates." "INFO"
		$result = [PSCustomObject]@{
			Passed   = $true
			Warnings = 1
		}
		if ($PassThru)
		{
			return $result
		}
		return
	}
	else
    {
		Write-Log "Found $($mtlsCertificates.Count) mTLS-capable GSA client certificate(s)." "SUCCESS"
	}

	# Iterate over each FQDN in the list and attempt mTLS connections.
	foreach ($fqdn in $fqdnList)
    {
		Write-Log "Attempting mTLS connection to: $fqdn on port $port" "INFO"

		foreach ($ClientCert in $mtlsCertificates)
        {
			$tcpClient = New-Object System.Net.Sockets.TcpClient
			try
            {
				$tcpClient.Connect($fqdn, $port)
				Write-Log "TCP connection successful to $fqdn" "SUCCESS"
			}
			catch
            {
				Write-Log "TCP connection failed to $fqdn : $($_.Exception.Message)" "ERROR"
				$allTestsPassed = $false
				continue
			}

			$sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, ({ $true }))
			try
            {
				# Prepare client certificate collection if provided.
				$clientCerts = New-Object System.Security.Cryptography.X509Certificates.X509CertificateCollection
				if ($ClientCert)
                { [void]$clientCerts.Add($ClientCert) }
				# Attempt the mTLS handshake using TLS 1.2
				$sslStream.AuthenticateAsClient($fqdn, $clientCerts, [System.Security.Authentication.SslProtocols]::Tls12, $false)
				$ismTLSdone = $sslStream.Ismutuallyauthenticated
				Write-Log "mTLS handshake succeeded for $fqdn with certificate $($ClientCert.Subject) mTLS: $ismTLSdone" "SUCCESS"
			}
			catch
            {
				if (-not $runningElevated)
                {
					Write-Log "mTLS handshake failed for $fqdn " "WARNING"
					Write-Log "Expected due to not running elevated. Run again with elevation" "WARNING"
					$warningsLogged = $true
				}
				else
                {
					Write-Log "mTLS handshake failed for $fqdn with certificate $($ClientCert.Subject) : $($_.Exception.Message)" "ERROR"
					$allTestsPassed = $false
				}
			}
			finally
            {
				$sslStream.Dispose()
				$tcpClient.Close()
			}
		}
	}

	# Determine the final result
	if (-not $allTestsPassed)
    {
		Write-Log "One or more mTLS connection attempts failed." "WARNING"
		$warningsLogged = $true
	}

	$result = [PSCustomObject]@{
		Passed   = $allTestsPassed
		Warnings = if ($warningsLogged) { 1 } else { 0 }
	}
	if ($PassThru)
	{
		return $result
	}
}

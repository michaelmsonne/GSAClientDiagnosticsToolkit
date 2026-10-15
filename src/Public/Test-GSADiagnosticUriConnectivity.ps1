#
# Function: Test-GSADiagnosticUriConnectivity
# Public function for the GSA client diagnostics toolkit.
#
function Test-GSADiagnosticUriConnectivity
{
	<#
.SYNOPSIS
	Tests reachability of GSA DiagnosticUris and reports round-trip time.
.PARAMETER DiagnosticUris
	List of diagnostic URIs to test.
#>
	[CmdletBinding()]
	param (
		[string[]]$DiagnosticUris,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	if (-not $DiagnosticUris -or $DiagnosticUris.Count -eq 0)
    {
		Write-Log "No DiagnosticUris to test." "WARNING"
		return $false
	}

	$allPassed = $true

	foreach ($uri in $DiagnosticUris)
    {
		try
        {
			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
			$response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 10
			$stopwatch.Stop()
			$rtt = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)

			if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300)
            {
				if ($rtt -gt 200)
                {
					Write-Log "DiagnosticUrl test $uri succeeded. RTT: $rtt ms (High RTT)" "WARNING"
				}
				else
                {
					Write-Log "DiagnosticUrl test $uri succeeded. RTT: $rtt ms" "SUCCESS"
				}
			}
			else
            {
				Write-Log "DiagnosticUrl test $uri returned status code $($response.StatusCode). RTT: $rtt ms" "WARNING"
				$allPassed = $false
			}
		}
		catch
        {
			Write-Log "DiagnosticUrl $uri failed: $($_.Exception.Message)" "ERROR"
			$allPassed = $false
		}
	}

	return $allPassed
}

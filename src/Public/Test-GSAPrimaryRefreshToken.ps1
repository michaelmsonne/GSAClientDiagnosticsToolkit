#
# Function: Test-GSAPrimaryRefreshToken
# Checks whether a Primary Refresh Token (PRT) is present on the device.
# Without a PRT the GSA client cannot authenticate with Entra ID.
#
function Test-GSAPrimaryRefreshToken
{
	<#
.SYNOPSIS
	Verifies that a Primary Refresh Token (PRT) is present on the device via dsregcmd.
.DESCRIPTION
	Parses 'dsregcmd /status' for the AzureAdPrt field.
	If the PRT is absent the GSA client cannot authenticate, regardless of device join state.
	Common causes: no network to Entra ID endpoints, Conditional Access blocking sign-in,
	or device health issues.
#>
	[CmdletBinding()]
	param (
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	Write-Log "Checking Primary Refresh Token (PRT) status via dsregcmd..." "INFO"

	try
    {
		$dsregOutput = dsregcmd /status 2>&1
		$prtPresent = ($dsregOutput | Select-String -Pattern 'AzureAdPrt' -SimpleMatch) -match 'YES'

		if ($prtPresent)
        {
			Write-Log "Primary Refresh Token (AzureAdPrt) is present - device can authenticate with Entra ID." "SUCCESS"
			if ($script:LogLevel -eq "DEBUG")
            {
				$prtTime = $dsregOutput | Select-String -Pattern '^\s*AzureAdPrtUpdateTime\s*:' | Select-Object -First 1
				if ($prtTime)
                { Write-Log "  AzureAdPrtUpdateTime : $(($prtTime.ToString() -split ':', 2)[1].Trim())" "DEBUG" }
			}
			return $true
		}
		else
        {
			Write-Log "Primary Refresh Token (AzureAdPrt) is NOT present. The GSA client cannot authenticate. Ensure the device is Entra Joined, has network connectivity to login.microsoftonline.com, and no Conditional Access policy is blocking sign-in." "ERROR"
			return $false
		}
	}
	catch
    {
		Write-Log "Failed to check PRT status via dsregcmd: $($_.Exception.Message)" "ERROR"
		return $false
	}
}

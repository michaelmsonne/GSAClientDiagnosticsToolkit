#
# Function: Invoke-GSAGraphRequest
# Thin Microsoft Graph wrapper that adds the Bearer token header and retries on HTTP 429 throttling.
# Falls back to an interactive Connect-MgGraph sign-in (via Invoke-MgGraphRequest) when no
# -AccessToken is supplied.
# Example: Invoke-GSAGraphRequest -AccessToken $token -Uri "https://graph.microsoft.com/v1.0/me"
#
function Invoke-GSAGraphRequest
{
	param (
		[string]$AccessToken,
		[string]$Uri,
		[string]$Method = "GET",
		[hashtable]$Body = $null,
		[string[]]$Scopes = @('NetworkAccess.Read.All', 'Application.Read.All', 'Directory.Read.All', 'User.Read.All')
	)

	if (-not $AccessToken)
    {
		Connect-GSAMgGraph -Scopes $Scopes
	}

	$maxRetries = 5
	$retryIntervalSeconds = 2

	for ($attempt = 0; $attempt -lt $maxRetries; $attempt++)
    {
		try
        {
			if ($AccessToken)
            {
				$headers = @{
					'Authorization' = "Bearer $AccessToken"
					'Content-Type'  = 'application/json'
				}
				if ($Method -eq 'GET' -or $null -eq $Body)
                {
					return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method
				}
				$jsonBody = $Body | ConvertTo-Json -Depth 10
				return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method -Body $jsonBody
			}

			# No explicit token - reuse the interactive Microsoft Graph SDK session instead
			if ($Method -eq 'GET' -or $null -eq $Body)
            {
				return Invoke-MgGraphRequest -Uri $Uri -Method $Method
			}
			return Invoke-MgGraphRequest -Uri $Uri -Method $Method -Body $Body
		}
		catch
        {
			$statusCode = $null
			if ($_.Exception.Response)
            { $statusCode = [int]$_.Exception.Response.StatusCode }
			elseif ($_.Exception.PSObject.Properties.Match('StatusCode').Count -gt 0) { $statusCode = [int]$_.Exception.StatusCode }

			if ($statusCode -eq 429)
            {
				$retryAfter = $null
				if ($_.Exception.Response)
                { $retryAfter = $_.Exception.Response.Headers['Retry-After'] }
				$waitSeconds = if ($retryAfter) { [int]$retryAfter } else { $retryIntervalSeconds * [math]::Pow(2, $attempt) }
				Write-Log "Throttled by Microsoft Graph (429). Retrying in $waitSeconds second(s)..." "WARNING"
				Start-Sleep -Seconds $waitSeconds
				continue
			}
			throw
		}
	}

	throw "Microsoft Graph request to '$Uri' failed after $maxRetries attempt(s) due to throttling."
}

#
# Function: Export-GSAEdgeAddresses
# Public function for the GSA client diagnostics toolkit.
#
function Export-GSAEdgeAddresses
{
	<#
.SYNOPSIS
	Saves a list of FQDNs/edge addresses to a file.
	If -fqdnList is omitted, the edge addresses are read from the GSA client forwarding profile (Get-GSAEndpoints).
.PARAMETER fqdnList
	Array of FQDNs to save. Defaults to the main endpoints of the local GSA client forwarding profile.
.PARAMETER filePath
	Destination file path. Defaults to GSAEdgeAddresses.txt in the current directory.
.EXAMPLE
	Export-GSAEdgeAddresses
.EXAMPLE
	Export-GSAEdgeAddresses -fqdnList @('edge1.example.com') -filePath C:\Temp\edges.txt
#>
	param (
		[string[]]$fqdnList,
		[string]$filePath
	)

	try
    {
		# No list supplied: fall back to the endpoints from the local GSA client configuration.
		if (-not $PSBoundParameters.ContainsKey('fqdnList'))
        {
			$endpoints = Get-GSAEndpoints
			if ($endpoints)
            {
				$fqdnList = @($endpoints.MainEndpoints)
			}
		}

		# Validate the input parameters before proceeding.
		if (-not $fqdnList -or $fqdnList.Count -eq 0)
        {
			Write-Log "No FQDNs provided to save." "ERROR"
			return
		}

		# No path supplied: default to a file in the current directory.
		if (-not $PSBoundParameters.ContainsKey('filePath'))
        {
			$filePath = Join-Path -Path (Get-Location).ProviderPath -ChildPath 'GSAEdgeAddresses.txt'
		}

		# Validate the file path parameter before proceeding.
		if (-not $filePath)
        {
			Write-Log "File path is not specified." "ERROR"
			return
		}

		# Ensure the directory for the file path exists, creating it if necessary.
		$directory = Split-Path -Path $filePath -Parent
		if ($directory -and -not (Test-Path $directory))
        {
			try
            {
				New-Item -ItemType Directory -Path $directory -Force | Out-Null
				Write-Log "Created directory: $directory" "INFO"
			}
			catch
            {
				Write-Log "Failed to create directory: $directory. Error: $($_.Exception.Message)" "ERROR"
				return
			}
		}

		$fqdnList | Out-File -Encoding utf8 $filePath -Force
		Write-Log "Edge addresses saved to: $filePath" "SUCCESS"
	}
	catch
    {
		Write-Log "Failed to save edge addresses to $filePath. Error: $($_.Exception.Message)" "ERROR"
	}
}

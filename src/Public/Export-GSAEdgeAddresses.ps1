#
# Function: Export-GSAEdgeAddresses
# Public function for the GSA client diagnostics toolkit.
#
function Export-GSAEdgeAddresses
{
	<#
.SYNOPSIS
	Saves a list of FQDNs/edge addresses to a file.
.PARAMETER fqdnList
	Array of FQDNs to save.
.PARAMETER filePath
	Destination file path.
#>
	param (
		[string[]]$fqdnList,
		[string]$filePath
	)

	try
    {
		# Validate the input parameters before proceeding.
		if (-not $fqdnList -or $fqdnList.Count -eq 0)
        {
			Write-Log "No FQDNs provided to save." "ERROR"
			return
		}

		# Validate the file path parameter before proceeding.
		if (-not $filePath)
        {
			Write-Log "File path is not specified." "ERROR"
			return
		}

		# Ensure the directory for the file path exists, creating it if necessary.
		$directory = Split-Path -Path $filePath -Parent
		if (-not (Test-Path $directory))
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

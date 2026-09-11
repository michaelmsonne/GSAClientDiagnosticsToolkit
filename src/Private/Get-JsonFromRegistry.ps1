# 
# Function: Load the ForwardingProfile from Registry
# 
function Get-JsonFromRegistry {
    param (
        [string]$ValueName = "ForwardingProfile"  # Adjust if the JSON is stored under a different value name
    )

    try {
        # Read the JSON string from the registry
        $jsonString = Get-ItemPropertyValue -Path $script:GSAFwdProfileRegistryPath -Name $ValueName -ErrorAction Stop
        if (-Not $jsonString) {
            Write-Log -Message "No JSON data found at registry path: $script:GSAFwdProfileRegistryPath" -Level "ERROR"
            return $null
        }
        $jsonContent = $jsonString | ConvertFrom-Json
        Write-Log -Message "Successfully read JSON data from registry path: $script:GSAFwdProfileRegistryPath" -Level "INFO"
        return $jsonContent
    }
    catch {
        Write-Log -Message "Failed to read JSON from registry: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

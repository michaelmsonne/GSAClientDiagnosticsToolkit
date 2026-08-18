function Get-JsonFromRegistry {
    param (
        [string]$ValueName = "ForwardingProfile"
    )

    try {
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
        Write-Log -Message "Failed to read JSON from registry: $_" -Level "ERROR"
        return $null
    }
}

#
# Function: Test-GSAForwardingProfileRegistry
# Verifies the GSA ForwardingProfile registry key exists, is non-empty, and is parseable JSON.
#
function Test-GSAForwardingProfileRegistry {
<#
.SYNOPSIS
    Verifies the GSA ForwardingProfile registry entry exists, is populated, and is valid JSON.
.DESCRIPTION
    Checks three things in order:
        1. The ForwardingProfile registry key exists under HKLM:\SOFTWARE\Microsoft\Global Secure Access Client
        2. The value is not empty
        3. The JSON is parseable and contains at least one channel
    Provides specific recommended actions for each failure point.
#>    [CmdletBinding()]
    param (
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }
    $allTestsPassed = $true
    $registryPath   = "HKLM:\SOFTWARE\Microsoft\Global Secure Access Client"
    $valueName      = "ForwardingProfile"

    # Check the registry key exists
    Write-Log "Checking ForwardingProfile registry key..." "INFO"
    $regProfile = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
    if (-Not $regProfile) {
        Write-Log "ForwardingProfile registry key does not exist. Ensure the forwarding profile is enabled and the user is assigned in Entra portal under Global Secure Access > Connect > Traffic forwarding." "ERROR"
        return $false
    }
    Write-Log "ForwardingProfile registry key exists." "SUCCESS"

    # Check the value is not empty
    Write-Log "Checking ForwardingProfile registry value is not empty..." "INFO"
    $profileValue = Get-ItemPropertyValue -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($profileValue)) {
        Write-Log "ForwardingProfile registry value is empty. Restart 'GlobalSecureAccessPolicyRetrieverService' (or 'GlobalSecureAccessForwardingProfileService') to re-retrieve the profile configuration." "ERROR"
        return $false
    }
    Write-Log "ForwardingProfile registry value is populated." "SUCCESS"

    # Validate the JSON is parseable
    Write-Log "Validating ForwardingProfile JSON..." "INFO"
    try {
        $json = $profileValue | ConvertFrom-Json
    } catch {
        Write-Log "ForwardingProfile JSON is corrupt or unparseable: $_. Restart 'GlobalSecureAccessPolicyRetrieverService' to refresh the profile." "ERROR"
        return $false
    }

    # Report which channels are configured
    $channels = $json.policy.channels
    if (-Not $channels -or $channels.Count -eq 0) {
        Write-Log "ForwardingProfile JSON contains no channels. Ensure at least one traffic forwarding profile (M365 / Private / Internet) is enabled in Entra portal." "WARNING"
        $allTestsPassed = $false
    } else {
        Write-Log "ForwardingProfile JSON is valid. Configured channel(s): $($channels.name -join ', ')." "SUCCESS"
        if ($script:LogLevel -eq "DEBUG") {
            if ($json.policy.tenantId) { Write-Log "  TenantId: $($json.policy.tenantId)" "DEBUG" }
            foreach ($ch in $channels) {
                $edges = @($ch.edgesSettings.primaryEdges) + @($ch.edgesSettings.secondaryEdges)
                Write-Log "  Channel '$($ch.name)': $($edges.Count) edge(s), DiagnosticUri: $($ch.diagnosticUri)" "DEBUG"
                foreach ($e in $edges) { Write-Log "    Edge: $($e.edgeAddress)" "DEBUG" }
            }
        }
    }

    return $allTestsPassed
}

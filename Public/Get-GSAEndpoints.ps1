function Get-GSAEndpoints {
<#
.SYNOPSIS
    Loads the GSA ForwardingProfile from the registry and returns endpoint and diagnostic URI lists.
.PARAMETER RegistryValueName
    Registry value name containing the GSA JSON policy (default: ForwardingProfile).
#>
    param (
        [string]$RegistryValueName = "ForwardingProfile"
    )

    $jsonContent = Get-JsonFromRegistry -ValueName $RegistryValueName
    [string[]]$DiagnosticUris       = @()
    [string[]]$gsaMainEndpointAddrs = @()

    if (-Not $jsonContent) {
        Write-Log "Failed to load GSA client configuration." "ERROR"
        return $null
    }

    $gsaChannels = Get-GSAMainEndpoints -jsonContent $jsonContent
    if ($gsaChannels.Count -eq 0) {
        Write-Log "No channels/edge addresses found." "ERROR"
        return $null
    }

    foreach ($entry in $gsaChannels) {
        Write-Log "Found channel: $($entry.ChannelName)" "DEBUG"
        foreach ($edge in $entry.EdgeAddresses) {
            $gsaMainEndpointAddrs += $edge
            Write-Log " -> Edge: $($edge)" "DEBUG"
        }
        Write-Log "Diagnostic URI: $($entry.DiagnosticUri)" "DEBUG"
        $DiagnosticUris += $entry.DiagnosticUri
    }

    $gsaMainEndpointAddrs += "aps.globalsecureaccess.microsoft.com"

    if ($gsaMainEndpointAddrs.Count -eq 0) { Write-Log "No edge addresses found." "ERROR"; return $null }
    if ($DiagnosticUris.Count -eq 0)        { Write-Log "No DiagnosticUris found." "ERROR"; return $null }

    return [PSCustomObject]@{
        MainEndpoints  = $gsaMainEndpointAddrs
        DiagnosticUris = $DiagnosticUris
    }
}

#
# Function: Test-GSAClientProfileConnectivity
# Public function for the GSA client diagnostics toolkit.
#
function Test-GSAClientProfileConnectivity {
    <#
.SYNOPSIS
    Tests local forwarding profile retrieval and edge/diagnostic connectivity for one or more GSA channels.
.DESCRIPTION
    Confirms the locally cached ForwardingProfile registry value contains a channel for the requested
    profile type(s) (m365/private/internet), tests TCP connectivity to each channel's primary edge
    (falling back to the secondary edge), and confirms each channel's diagnostic endpoint responds with
    HTTP 200 and body 'pong'. This is a fully local/offline check; it does not call Microsoft Graph.
.PARAMETER ProfileType
    The forwarding profile channel(s) to test: m365, private, and/or internet. Defaults to all three
    when not specified.
.PARAMETER RegistryValueName
    Registry value name containing the GSA JSON policy (default: ForwardingProfile).
.PARAMETER PassThru
    Return the $true/$false test result (across all tested profiles). By default nothing is returned - only logged.
.EXAMPLE
    Test-GSAClientProfileConnectivity -ProfileType private
.EXAMPLE
    Test-GSAClientProfileConnectivity
#>
    [CmdletBinding()]
    param (
        [ValidateSet("m365", "private", "internet")]
        [string[]]$ProfileType,
        [string]$RegistryValueName = "ForwardingProfile",
        [switch]$PassThru,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    # No profile specified - test every channel
    if (-not $ProfileType -or @($ProfileType).Count -eq 0) {
        $ProfileType = @('m365', 'private', 'internet')
    }

    $profileNames = @{ m365 = "Microsoft Traffic"; private = "Private Access"; internet = "Internet Access" }
    $allPassed = $true

    foreach ($type in @($ProfileType)) {
        $profileName = $profileNames[$type]

        Write-Log "Checking $profileName profile..." "INFO"

        $jsonContent = Get-JsonFromRegistry -ValueName $RegistryValueName
        if (-not $jsonContent) {
            Write-Log "Failed to load GSA client configuration from the registry." "ERROR"
            $allPassed = $false
            continue
        }

        $channel = @($jsonContent.policy.channels) | Where-Object { $_.name -eq $type } | Select-Object -First 1
        if (-not $channel) {
            Write-Log "$profileName forwarding profile channel was not retrieved." "ERROR"
            Write-Log "Recommended action: Ensure the $profileName forwarding profile is enabled and the user is assigned in Entra portal under Global Secure Access > Connect > Traffic forwarding." "WARNING"
            $allPassed = $false
            continue
        }
        Write-Log "$profileName forwarding profile configuration has been retrieved." "SUCCESS"

        $primaryEdge = $channel.edgesSettings.primaryEdges | Select-Object -First 1
        $secondaryEdge = $channel.edgesSettings.secondaryEdges | Select-Object -First 1
        $diagnosticUri = $channel.diagnosticUri

        Write-Log "Checking connectivity to $profileName edge..." "INFO"
        $primaryReachable = $primaryEdge -and (Test-NetConnection -ComputerName $primaryEdge.edgeAddress -Port $primaryEdge.edgePort -InformationLevel Quiet -WarningAction SilentlyContinue)
        if ($primaryReachable) {
            Write-Log "Connection to the $profileName primary edge ($($primaryEdge.edgeAddress):$($primaryEdge.edgePort)) succeeded." "SUCCESS"
        }
        else {
            Write-Log "Failed to connect to the $profileName primary edge, checking the secondary edge..." "WARNING"
            $secondaryReachable = $secondaryEdge -and (Test-NetConnection -ComputerName $secondaryEdge.edgeAddress -Port $secondaryEdge.edgePort -InformationLevel Quiet -WarningAction SilentlyContinue)
            if (-not $secondaryReachable) {
                Write-Log "Unable to connect to any $profileName edge." "ERROR"
                Write-Log "Recommended action: Ensure outbound connectivity to the following $profileName edges is allowed: $($primaryEdge.edgeAddress), $($secondaryEdge.edgeAddress)." "WARNING"
                $allPassed = $false
                continue
            }
            Write-Log "Connection to the $profileName secondary edge ($($secondaryEdge.edgeAddress):$($secondaryEdge.edgePort)) succeeded." "SUCCESS"
        }

        Write-Log "Checking connectivity to the $profileName diagnostic endpoint..." "INFO"
        try {
            $healthCheck = Invoke-WebRequest -Uri $diagnosticUri -UseBasicParsing
        }
        catch {
            Write-Log "Failed to connect to the $profileName diagnostic endpoint ($diagnosticUri): $($_.Exception.Message)" "ERROR"
            Write-Log "Recommended action: Ensure outbound traffic to $diagnosticUri is allowed." "WARNING"
            $allPassed = $false
            continue
        }
        if ($healthCheck.StatusCode -ne 200 -or $healthCheck.Content -ne 'pong') {
            Write-Log "The $profileName diagnostic endpoint did not respond as expected." "ERROR"
            Write-Log "Recommended action: Ensure outbound traffic to $diagnosticUri is allowed." "WARNING"
            $allPassed = $false
            continue
        }
        Write-Log "Connection to the $profileName diagnostic endpoint succeeded." "SUCCESS"
    }

    if ($PassThru) { return $allPassed }
}

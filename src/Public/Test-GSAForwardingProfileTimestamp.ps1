#
# Function: Test-GSAForwardingProfileTimestamp
# Checks the ForwardingProfileTimestamp registry value to detect stale profiles.
# The cloudcoffee.ch troubleshooting guide notes this key shows the last UTC update time;
# changes in the portal can take up to one hour to reach the client.
#
function Test-GSAForwardingProfileTimestamp {
    <#
.SYNOPSIS
    Checks when the GSA ForwardingProfile was last retrieved from Microsoft Graph.
.DESCRIPTION
    Reads HKLM:\SOFTWARE\Microsoft\Global Secure Access Client\ForwardingProfileTimestamp
    and reports the age of the profile. A missing value means the profile was never
    downloaded. A value older than 2 hours is flagged as a warning since profile changes
    can take up to 1 hour to propagate; older than that suggests a retrieval failure.
    Fix: delete ForwardingProfileTimestamp and restart GlobalSecureAccessForwardingProfileService.
#>    [CmdletBinding()]
    param (
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Global Secure Access Client"
    $valueName = "ForwardingProfileTimestamp"
    $warnAgeHours = 2

    Write-Log "Checking ForwardingProfileTimestamp registry value..." "INFO"
    $timestampValue = Get-ItemPropertyValue -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue

    if ([string]::IsNullOrEmpty($timestampValue)) {
        Write-Log "ForwardingProfileTimestamp is missing - the forwarding profile has never been downloaded. Ensure network connectivity to graph.microsoft.com and that the user is assigned to a forwarding profile in Entra portal." "WARNING"
        return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
    }

    try {
        $profileTime = [datetime]::Parse($timestampValue, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
        $age = (Get-Date).ToUniversalTime() - $profileTime.ToUniversalTime()
        $ageFormatted = "$([int]$age.TotalHours)h $($age.Minutes)m"

        if ($age.TotalHours -le $warnAgeHours) {
            Write-Log "ForwardingProfile was last retrieved $ageFormatted ago (UTC: $($profileTime.ToString('u'))) - profile is current." "SUCCESS"
            return $true
        }
        else {
            Write-Log "ForwardingProfile was last retrieved $ageFormatted ago (UTC: $($profileTime.ToString('u'))) - profile may be stale. To force a refresh: delete the ForwardingProfileTimestamp registry key and restart GlobalSecureAccessForwardingProfileService." "WARNING"
            return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
        }
    }
    catch {
        Write-Log "ForwardingProfileTimestamp value '$timestampValue' could not be parsed as a date: $($_.Exception.Message)" "WARNING"
        return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
    }
}

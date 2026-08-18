#
# Function: Test-DeviceEntraStatus
# Checks that the device is Entra Joined (or Hybrid Entra Joined) and that
# Private Access has not been disabled by a local user registry setting.
#
function Test-DeviceEntraStatus {
<#
.SYNOPSIS
    Verifies the device is connected to Microsoft Entra ID and that Private Access is not user-disabled.
.DESCRIPTION
    1. Runs dsregcmd /status to confirm AzureADJoined = YES (Entra Joined or Hybrid Entra Joined).
    2. Reads HKCU\Software\Microsoft\Global Secure Access Client\IsPrivateAccessDisabledByUser
       and warns if Private Access has been switched off by the user.
#>
    $allTestsPassed = $true

    # Check Entra ID join status via dsregcmd
    Write-Log "Checking if device is connected to Microsoft Entra ID..." "INFO"
    try {
        $dsregOutput   = dsregcmd /status 2>&1
        $entraJoined   = ($dsregOutput | Select-String -Pattern 'AzureADJoined' -SimpleMatch) -match 'YES'

        if ($entraJoined) {
            Write-Log "Device '$($env:COMPUTERNAME)' is connected to Microsoft Entra ID." "SUCCESS"
            if ($script:LogLevel -eq "DEBUG") {
                foreach ($field in @('DomainJoined', 'TenantId', 'TenantDisplayName', 'AzureAdPrtUpdateTime')) {
                    $line = $dsregOutput | Select-String -Pattern "^\s*$field\s*:" | Select-Object -First 1
                    if ($line) { Write-Log "  $field : $(($line.ToString() -split ':', 2)[1].Trim())" "DEBUG" }
                }
            }
        } else {
            Write-Log "Device '$($env:COMPUTERNAME)' is NOT connected to Microsoft Entra ID. Ensure the device is Entra Joined or Hybrid Entra Joined." "ERROR"
            $allTestsPassed = $false
        }
    } catch {
        Write-Log "Failed to determine Entra ID join status via dsregcmd: $_" "ERROR"
        $allTestsPassed = $false
    }

    # Check if user has locally disabled Private Access
    Write-Log "Checking Private Access user-disable registry flag..." "INFO"
    $reg = Get-ItemProperty -Path 'Registry::HKCU\Software\Microsoft\Global Secure Access Client' -ErrorAction SilentlyContinue
    if ($reg.IsPrivateAccessDisabledByUser -eq 1) {
        Write-Log "Private Access is disabled by user setting (IsPrivateAccessDisabledByUser = 1). Set the value to 0 in HKCU\Software\Microsoft\Global Secure Access Client to re-enable." "WARNING"
        # Treat as warning only - user may intentionally have it off; do not fail the test
    } else {
        Write-Log "Private Access is enabled (IsPrivateAccessDisabledByUser is not set or is 0)." "SUCCESS"
    }

    return $allTestsPassed
}

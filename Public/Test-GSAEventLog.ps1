#
# Function: Test-GSAEventLog
# Reads the GSA Windows Event Log (Operational channel) for recent Critical/Error events.
# Provides quick visibility into authentication, connection, or driver failures logged
# by the GSA client without needing to open Event Viewer manually.
#
function Test-GSAEventLog {
<#
.SYNOPSIS
    Scans the GSA Operational event log for Critical or Error events in the last hour.
.DESCRIPTION
    Reads up to 200 events from 'Microsoft-Global Secure Access Client/Operational'
    and reports any Level 1 (Critical) or Level 2 (Error) entries recorded in the last hour.
    If errors are found they are logged as warnings with EventId and truncated message.
    The test does not fail on log errors - it is diagnostic-only.
#>
    $lookbackHours = 1
    $maxEvents     = 200

    # Discover the GSA event log name - Channel field from exported XML: 'Microsoft-Windows-Global Secure Access Client-Operational'
    $candidateNames = @(
        "Microsoft-Windows-Global Secure Access Client-Operational",
        "Microsoft-Windows-Global Secure Access Client-Kernel"
    )
    $logName = $candidateNames | Where-Object {
        Get-WinEvent -ListLog $_ -ErrorAction SilentlyContinue
    } | Select-Object -First 1

    if (-not $logName) {
        Write-Log "GSA event log not found on this system. The log channel has not been registered yet (this is normal on new installs or if no events have occurred)." "WARNING"
        return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
    }

    # Known event IDs with semantic category - from operational log enumeration
    $knownEvents = @{
        # Connection handling and errors
        141 = @{ Category = 'Connection';      Description = 'Edge connection FAILED (GRPC could not be established)' }
        212 = @{ Category = 'Connection';      Description = 'Flow closed by server (private resource unreachable)' }
        230 = @{ Category = 'Connection';      Description = 'Private Access channel disabled' }
        631 = @{ Category = 'Connection';      Description = 'Disconnected from ALL channels' }
        632 = @{ Category = 'Connection';      Description = 'Partially connected - some channels are down' }
        638 = @{ Category = 'Connection';      Description = 'Device not connected to the network' }
        # Authentication handling
        503 = @{ Category = 'Authentication';  Description = 'User authenticated successfully' }
    }

    Write-Log "Scanning GSA event log '$logName' for Critical/Error/Warning events in the last $lookbackHours hour(s)..." "INFO"

    try {
        $since   = (Get-Date).AddHours(-$lookbackHours)
        $all     = Get-WinEvent -LogName $logName -MaxEvents $maxEvents -ErrorAction Stop
        $errors  = $all | Where-Object { $_.TimeCreated -ge $since -and $_.Level -le 3 }

        if (-not $errors -or $errors.Count -eq 0) {
            Write-Log "No Critical/Error/Warning events found in the GSA event log in the last $lookbackHours hour(s)." "SUCCESS"
            if ($script:LogLevel -eq "DEBUG") {
                $recentAll = $all | Where-Object { $_.TimeCreated -ge $since } | Select-Object -First 20
                if ($recentAll) {
                    Write-Log "  Recent events (all levels, last $lookbackHours hour):" "DEBUG"
                    foreach ($ev in $recentAll) {
                        $msg = ($ev.Message -replace '\s+', ' ').Trim()
                        if ($msg.Length -gt 150) { $msg = $msg.Substring(0, 147) + '...' }
                        $cat = if ($knownEvents.ContainsKey($ev.Id)) { $knownEvents[$ev.Id].Category } else { '' }
                        $catLabel = if ($cat) { "[$cat] " } else { '' }
                        Write-Log "  [$($ev.TimeCreated.ToString('HH:mm:ss'))] L$($ev.Level) EventId $($ev.Id) ${catLabel}: $msg" "DEBUG"
                    }
                }
            }
            return $true
        }

        Write-Log "Found $($errors.Count) Critical/Error/Warning event(s) in the GSA event log (last $lookbackHours hour):" "WARNING"
        foreach ($ev in ($errors | Select-Object -First 10)) {
            $known    = $knownEvents[$ev.Id]
            $catLabel = if ($known) { "[$($known.Category)] " } else { '' }
            $desc     = if ($known) { " ($($known.Description))" } else { '' }
            $msg      = ($ev.Message -replace '\s+', ' ').Trim()
            if ($msg.Length -gt 150) { $msg = $msg.Substring(0, 147) + '...' }
            Write-Log "  [$($ev.TimeCreated.ToString('HH:mm:ss'))] ${catLabel}EventId $($ev.Id)$desc" "WARNING"
            Write-Log "    $msg" "WARNING"
        }
        if ($errors.Count -gt 10) {
            Write-Log "  ... and $($errors.Count - 10) more event(s). Open Event Viewer for full details." "WARNING"
        }

        return [PSCustomObject]@{ Passed = $true; Warnings = $errors.Count }
    } catch {
        if ($_.Exception.Message -match "No events were found|not found") {
            Write-Log "No events in the GSA event log for the last $lookbackHours hour(s)." "SUCCESS"
            return $true
        }
        # Log not accessible (e.g. not yet created on a new install) - treat as warning
        Write-Log "Could not read GSA event log '$logName': $_" "WARNING"
        return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
    }
}

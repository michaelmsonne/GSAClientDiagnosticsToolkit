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
    Reads up to 200 events from 'Microsoft-Windows-GlobalSecureAccess-Client/Operational'
    and reports any Level 1 (Critical) or Level 2 (Error) entries recorded in the last hour.
    If errors are found they are logged as warnings with EventId and truncated message.
    The test does not fail on log errors — it is diagnostic-only.
#>
    $logName       = "Microsoft-Windows-GlobalSecureAccess-Client/Operational"
    $lookbackHours = 1
    $maxEvents     = 200

    Write-Log "Scanning GSA event log for Critical/Error events in the last $lookbackHours hour(s)..." "INFO"

    try {
        $since   = (Get-Date).AddHours(-$lookbackHours)
        $all     = Get-WinEvent -LogName $logName -MaxEvents $maxEvents -ErrorAction Stop
        $errors  = $all | Where-Object { $_.TimeCreated -ge $since -and $_.Level -le 2 }

        if (-not $errors -or $errors.Count -eq 0) {
            Write-Log "No Critical or Error events found in the GSA event log in the last $lookbackHours hour(s)." "SUCCESS"
            return $true
        }

        Write-Log "Found $($errors.Count) Critical/Error event(s) in the GSA event log (last $lookbackHours hour):" "WARNING"
        foreach ($ev in ($errors | Select-Object -First 5)) {
            $msg = ($ev.Message -replace '\s+', ' ').Trim()
            if ($msg.Length -gt 200) { $msg = $msg.Substring(0, 197) + '...' }
            Write-Log "  [$($ev.TimeCreated.ToString('HH:mm:ss'))] EventId $($ev.Id): $msg" "WARNING"
        }
        if ($errors.Count -gt 5) {
            Write-Log "  ... and $($errors.Count - 5) more event(s). Open Event Viewer for full details." "WARNING"
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

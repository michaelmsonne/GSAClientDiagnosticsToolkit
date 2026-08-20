#
# Function: Test-GSASyntheticRoutes
# Checks whether GSA synthetic IP routes (6.6.x.x) are present in the routing table.
# GSA assigns synthetic 6.6.x.x addresses to tunneled resources; when the tunnel is active
# these prefixes appear as host or /32 routes in the Windows routing table.
#
function Test-GSASyntheticRoutes {
    <#
.SYNOPSIS
    Checks for GSA synthetic IP routes (6.6.x.x) in the Windows routing table.
.DESCRIPTION
    When the GSA tunnel is active and traffic is being forwarded, Windows routes for
    synthetic 6.6.x.x addresses appear in the routing table. Absence of these routes
    indicates the tunnel may not be active or no tunneled traffic has flowed yet.
    This is a WARNING-only test (not a hard failure) since routes only appear dynamically.
#>
    [CmdletBinding()]
    param (
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    Write-Log "Checking for GSA synthetic IP routes (6.6.x.x) in the routing table..." "INFO"

    try {
        $gsaRoutes = Get-NetRoute -ErrorAction Stop | Where-Object { $_.DestinationPrefix -like "6.6.*" }
    }
    catch {
        Write-Log "Failed to query routing table: $_" "ERROR"
        return $false
    }

    if ($gsaRoutes -and $gsaRoutes.Count -gt 0) {
        Write-Log "Found $($gsaRoutes.Count) GSA synthetic route(s) - tunnel is active and routing traffic." "SUCCESS"
        foreach ($route in $gsaRoutes) {
            Write-Log "  $($route.DestinationPrefix) via $($route.NextHop) (interface: $($route.InterfaceAlias))" "DEBUG"
        }
        return $true
    }
    else {
        Write-Log "No GSA synthetic IP routes (6.6.x.x) found. The tunnel may not be active yet - this is expected if no Private/M365/Internet traffic has flowed since the client started." "WARNING"
        return [PSCustomObject]@{
            Passed   = $true
            Warnings = 1
        }
    }
}

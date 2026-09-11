#
# Function: Test-EntraIDUserAuthN
# Public function for the GSA client diagnostics toolkit.
#
function Test-EntraIDUserAuthN {
    <#
.SYNOPSIS
    Attempts interactive authentication to Entra ID using MSAL. Requires the MSAL.PS module.
#>
    try {
        Write-Log -Message "Attempting authentication to Entra ID" -Level "INFO"
        $token = Get-MSALToken -ClientId "d3590ed6-52b3-4102-aeff-aad2292ab01c" -Scopes "https://graph.microsoft.com/.default"

        if ($token.AccessToken) {
            Write-Log -Message "Authentication successful. Token retrieved." -Level "INFO"
        }
        else {
            Write-Log -Message "Authentication failed. No token received." -Level "ERROR"
        }
    }
    catch {
        Write-Log -Message "Authentication failed: $($_.Exception.Message)" -Level "ERROR"
    }
}

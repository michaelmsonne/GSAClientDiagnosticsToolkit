#
# Function: Get-GSAPrivateAccessApplicationDisplayNames
# Resolves Private Access/Quick Access application IDs to display names via Microsoft Graph, using the
# same tags/Any filter the Entra admin portal uses to list apps eligible for Private Networks (ILA).
# Example: Get-GSAPrivateAccessApplicationDisplayNames -AccessToken $token
#
function Get-GSAPrivateAccessApplicationDisplayNames {
    param (
        [string]$AccessToken
    )

    $map = @{}
    $filter = "tags/Any(x:x eq 'IsAccessibleViaZTNAClient') or tags/Any(x:x eq 'NetworkAccessQuickAccessApplication')"
    $uri = "https://graph.microsoft.com/beta/applications?`$filter=$([uri]::EscapeDataString($filter))&`$select=appId,displayName&`$top=999"

    try {
        $result = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri $uri
    }
    catch {
        Write-Log "Failed to resolve Private Access/Quick Access application display names via Microsoft Graph: $_" "DEBUG"
        return $map
    }

    foreach ($app in @($result.value)) {
        if ($app.appId) { $map[$app.appId] = $app.displayName }
    }
    return $map
}

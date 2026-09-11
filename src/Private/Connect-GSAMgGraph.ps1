#
# Function: Connect-GSAMgGraph
# Ensures an authenticated Microsoft Graph SDK session (with the required scopes) exists,
# prompting an interactive sign-in via Connect-MgGraph only if one isn't already active.
# Example: Connect-GSAMgGraph -Scopes @('User.Read.All')
#
function Connect-GSAMgGraph
{
	param (
		[string[]]$Scopes = @('NetworkAccess.Read.All', 'Application.Read.All', 'Directory.Read.All', 'User.Read.All')
	)

	if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication))
    {
		throw "No -AccessToken was supplied and the 'Microsoft.Graph.Authentication' module is not installed. Install it with 'Install-Module Microsoft.Graph.Authentication -Scope CurrentUser' to sign in interactively, or supply -AccessToken directly."
	}

	Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

	$context = Get-MgContext
	$missingScopes = @($Scopes | Where-Object { $context.Scopes -notcontains $_ })

	if (-not $context -or $missingScopes.Count -gt 0)
    {
		Write-Log "No active Microsoft Graph sign-in found (or missing required scope(s): $($missingScopes -join ', ')). Prompting for interactive sign-in..." "INFO"
		Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
	}
}

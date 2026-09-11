#
# Function: Test-GSAForwardingProfileAssignment
# Public function for the GSA client diagnostics toolkit.
#
function Test-GSAForwardingProfileAssignment
{
	<#
.SYNOPSIS
	Checks via Microsoft Graph that a GSA forwarding profile is enabled and the user is assigned to it.
.DESCRIPTION
	Verifies the tenant is onboarded to Global Secure Access, that the requested forwarding profile
	(m365/private/internet) is enabled, and that the target user is directly assigned - or a member of
	a group assigned - to that profile's enterprise application (service principal).
.PARAMETER AccessToken
	A Microsoft Graph access token with NetworkAccess.Read.All, Application.Read.All, Directory.Read.All,
	and User.Read.All permissions (e.g. obtained via Test-EntraIDUserAuthN or your own MSAL/Graph sign-in).
	If omitted, an interactive Connect-MgGraph sign-in is triggered automatically (requires the
	Microsoft.Graph.Authentication module), reusing any already-active Graph session.
.PARAMETER ProfileType
	The forwarding profile to check: m365, private, or internet.
.PARAMETER UserPrincipalName
	UPN of the user to check assignment for. Defaults to the currently signed-in Windows user (whoami /upn).
.PARAMETER PassThru
	Return the $true/$false test result. By default nothing is returned - only logged.
.EXAMPLE
	Test-GSAForwardingProfileAssignment -AccessToken $token -ProfileType private
.EXAMPLE
	Test-GSAForwardingProfileAssignment -ProfileType private
.EXAMPLE
	Test-GSAForwardingProfileAssignment -ProfileType m365 -UserPrincipalName user@domain.com
#>
	[CmdletBinding()]
	param (
		[string]$AccessToken,
		[Parameter(Mandatory)]
		[ValidateSet("m365", "private", "internet")]
		[string]$ProfileType,
		[string]$UserPrincipalName,
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	$profileNames = @{ m365 = "Microsoft Traffic"; private = "Private Access"; internet = "Internet Access" }
	$profileName = $profileNames[$ProfileType]

	if (-not $UserPrincipalName)
    { $UserPrincipalName = Get-GSACurrentUserUPN }
	if (-not $UserPrincipalName)
    {
		Write-Log "Unable to determine the current user's UPN. Specify -UserPrincipalName explicitly." "ERROR"
		if ($PassThru)
        { return $false }
		return
	}

	Write-Log "Checking the Global Secure Access activation status..." "INFO"
	try
    {
		$tenantStatus = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/beta/networkAccess/tenantStatus"
	}
	catch
    {
		Write-Log "Failed to check tenant onboarding status via Microsoft Graph: $($_.Exception.Message)" "ERROR"
		if ($PassThru)
        { return $false }
		return
	}
	if ($tenantStatus.onboardingStatus -ne 'onboarded')
    {
		Write-Log "Global Secure Access is NOT activated on the tenant." "ERROR"
		Write-Log "Recommended action: Activate Global Secure Access in Entra > Global Secure Access > Get started > Activate Global Secure Access in your tenant." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	Write-Log "Global Secure Access is activated in the tenant." "SUCCESS"

	Write-Log "Checking the $profileName forwarding profile..." "INFO"
	try
    {
		$profilesResult = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/beta/networkAccess/forwardingProfiles?`$filter=trafficForwardingType eq '$ProfileType'"
	}
	catch
    {
		Write-Log "Failed to retrieve the $profileName forwarding profile via Microsoft Graph: $($_.Exception.Message)" "ERROR"
		if ($PassThru)
        { return $false }
		return
	}
	$forwardingProfile = @($profilesResult.value)[0]
	if (-not $forwardingProfile -or $forwardingProfile.state -ne 'enabled')
    {
		Write-Log "$profileName forwarding profile is NOT enabled." "ERROR"
		Write-Log "Recommended action: Enable the $profileName profile from Entra > Global Secure Access > Connect > Traffic forwarding." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	Write-Log "$profileName forwarding profile is enabled." "SUCCESS"

	Write-Log "Checking user assignment to the $profileName forwarding profile..." "INFO"
	$servicePrincipalId = $forwardingProfile.servicePrincipal.id
	try
    {
		$sp = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId`?`$select=id,appid,accountEnabled,appRoleAssignmentRequired&`$expand=appRoleAssignedTo(`$select=principalId,principalType,principalDisplayName)"
	}
	catch
    {
		Write-Log "Failed to retrieve the $profileName service principal via Microsoft Graph: $($_.Exception.Message)" "ERROR"
		if ($PassThru)
        { return $false }
		return
	}

	$assignedUsers = @($sp.appRoleAssignedTo) | Where-Object { $_.principalType -eq 'User' }
	$assignedGroupIds = @($sp.appRoleAssignedTo) | Where-Object { $_.principalType -eq 'Group' } | ForEach-Object { $_.principalId }

	$assigned = Test-GSAAppRoleAssignment -AccessToken $AccessToken -UserPrincipalName $UserPrincipalName -AssignmentRequired ([bool]$sp.appRoleAssignmentRequired) -AssignedUsers $assignedUsers -AssignedGroupIds $assignedGroupIds
	if (-not $assigned)
    {
		Write-Log "'$UserPrincipalName' is NOT assigned (directly or via group) to the $profileName profile." "ERROR"
		Write-Log "Recommended action: Assign the user directly, or via group membership, to the $profileName profile's enterprise application in Entra." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	Write-Log "'$UserPrincipalName' is assigned to the $profileName profile." "SUCCESS"

	if ($PassThru)
    { return $true }
}

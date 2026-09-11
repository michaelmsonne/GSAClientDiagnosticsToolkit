#
# Function: Test-GSAPrivateAccessApplicationSegment
# Public function for the GSA client diagnostics toolkit.
#
function Test-GSAPrivateAccessApplicationSegment
{
	<#
.SYNOPSIS
	Checks via Microsoft Graph that a Private Access application is enabled, the user is assigned, and
	the target FQDN/IP + port + protocol is covered by one of its application segments.
.DESCRIPTION
	Retrieves the application's service principal, verifies it is enabled and the user is assigned
	(directly or via group), then retrieves its onPremisesPublishing application segments and checks
	whether the target FQDN/IP, port, and protocol are configured on one of them.
.PARAMETER AccessToken
	A Microsoft Graph access token with Application.Read.All and User.Read.All permissions.
	If omitted, an interactive Connect-MgGraph sign-in is triggered automatically (requires the
	Microsoft.Graph.Authentication module), reusing any already-active Graph session.
.PARAMETER AppId
	The Private Access application's (client) App ID.
.PARAMETER FQDNorIP
	The target FQDN or IPv4 address to test.
.PARAMETER Port
	The target port number.
.PARAMETER Protocol
	The protocol to test (TCP or UDP).
.PARAMETER UserPrincipalName
	UPN of the user to check assignment for. Defaults to the currently signed-in Windows user (whoami /upn).
.PARAMETER PassThru
	Return the $true/$false test result. By default nothing is returned - only logged.
.EXAMPLE
	Test-GSAPrivateAccessApplicationSegment -AccessToken $token -AppId $appId -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP
#>
	[CmdletBinding()]
	param (
		[string]$AccessToken,
		[Parameter(Mandatory)]
		[string]$AppId,
		[Parameter(Mandatory)]
		[string]$FQDNorIP,
		[Parameter(Mandatory)]
		[int]$Port,
		[Parameter(Mandatory)]
		[ValidateSet("TCP", "UDP")]
		[string]$Protocol,
		[string]$UserPrincipalName,
		[switch]$PassThru,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$LogLevel
	)

	if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

	$inputType = Test-IPorFQDN -FQDNorIP $FQDNorIP
	if (-not $inputType)
    {
		Write-Log "'$FQDNorIP' is not a valid IPv4 address or FQDN." "ERROR"
		if ($PassThru)
        { return $false }
		return
	}

	if (-not $UserPrincipalName)
    { $UserPrincipalName = Get-GSACurrentUserUPN }
	if (-not $UserPrincipalName)
    {
		Write-Log "Unable to determine the current user's UPN. Specify -UserPrincipalName explicitly." "ERROR"
		if ($PassThru)
        { return $false }
		return
	}

	Write-Log "Checking Private Access application status..." "INFO"
	try
    {
		$spResult = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appid eq '$AppId'&`$select=id,appid,accountEnabled,appRoleAssignmentRequired&`$expand=appRoleAssignedTo(`$select=principalId,principalType,principalDisplayName)"
	}
	catch
    {
		Write-Log "Failed to retrieve the Private Access application via Microsoft Graph: $($_.Exception.Message)" "ERROR"
		if ($PassThru)
        { return $false }
		return
	}
	$sp = @($spResult.value)[0]
	if (-not $sp)
    {
		Write-Log "No Private Access application found with App ID '$AppId'." "ERROR"
		if ($PassThru)
        { return $false }
		return
	}
	$appObjectId = $sp.id

	if (-not $sp.accountEnabled)
    {
		Write-Log "Private Access application (App ID: $AppId) is disabled." "ERROR"
		Write-Log "Recommended action: Enable the Private Access application (App ID: $AppId)." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	Write-Log "Private Access application (App ID: $AppId) is enabled." "SUCCESS"

	Write-Log "Checking Private Access application user assignment..." "INFO"
	$assignedUsers = @($sp.appRoleAssignedTo) | Where-Object { $_.principalType -eq 'User' }
	$assignedGroupIds = @($sp.appRoleAssignedTo) | Where-Object { $_.principalType -eq 'Group' } | ForEach-Object { $_.principalId }
	$assigned = Test-GSAAppRoleAssignment -AccessToken $AccessToken -UserPrincipalName $UserPrincipalName -AssignmentRequired ([bool]$sp.appRoleAssignmentRequired) -AssignedUsers $assignedUsers -AssignedGroupIds $assignedGroupIds
	if (-not $assigned)
    {
		Write-Log "'$UserPrincipalName' is NOT assigned (directly or via group) to the Private Access application (App ID: $AppId)." "ERROR"
		Write-Log "Recommended action: Assign the user directly, or via group membership, to the application (App ID: $AppId)." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	Write-Log "'$UserPrincipalName' is assigned to the Private Access application (App ID: $AppId)." "SUCCESS"

	Write-Log "Checking the application segment configuration for '${FQDNorIP}:${Port}/${Protocol}'..." "INFO"
	try
    {
		$segmentsResult = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/beta/applications/$appObjectId/onPremisesPublishing/segmentsConfiguration/microsoft.graph.ipSegmentConfiguration/applicationSegments"
	}
	catch
    {
		Write-Log "Failed to retrieve application segments via Microsoft Graph: $($_.Exception.Message)" "ERROR"
		if ($PassThru)
        { return $false }
		return
	}
	$segments = @($segmentsResult.value)
	if ($segments.Count -eq 0)
    {
		Write-Log "No application segments are configured for App ID: $AppId." "ERROR"
		if ($PassThru)
        { return $false }
		return
	}

	$match = Get-GSAApplicationSegmentMatch -Segments $segments -FQDNorIP $FQDNorIP -InputType $inputType -Port $Port -Protocol $Protocol

	if (-not $match.AddressMatched)
    {
		Write-Log "'$FQDNorIP' is not configured in any application segment for App ID: $AppId." "ERROR"
		Write-Log "Recommended action: Ensure you entered a valid FQDN/IP and it is configured in the Private Access application (App ID: $AppId)." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	if (-not $match.PortMatched)
    {
		Write-Log "Port $Port is NOT configured for App ID: $AppId." "ERROR"
		Write-Log "Recommended action: Ensure you entered the correct port and it is configured in the Private Access application (App ID: $AppId)." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	if (-not $match.ProtocolMatched)
    {
		Write-Log "Protocol $Protocol is NOT configured for port $Port on App ID: $AppId." "ERROR"
		Write-Log "Recommended action: Ensure you entered the correct protocol and it is configured in the Private Access application (App ID: $AppId)." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}

	Write-Log "Test passed: '$FQDNorIP' on port $Port/$Protocol is configured for the Private Access application (App ID: $AppId)." "SUCCESS"
	if ($PassThru)
    { return $true }
}

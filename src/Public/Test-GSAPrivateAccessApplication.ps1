#
# Function: Test-GSAPrivateAccessApplication
# Public function for the GSA client diagnostics toolkit.
#
function Test-GSAPrivateAccessApplication
{
	<#
.SYNOPSIS
	Full end-to-end Private Access application check: Entra configuration plus a live tunnel test.
.DESCRIPTION
	Confirms the application has "Enable access with Global Secure Access client" turned on, that its
	Entra configuration (enablement, user assignment, application segment) permits the target FQDN/IP,
	port, and protocol via Test-GSAPrivateAccessApplicationSegment, and then verifies the traffic
	actually tunnels through GSA via Test-GSAPrivateAccessTunnel.
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
	Test-GSAPrivateAccessApplication -AccessToken $token -AppId $appId -FQDNorIP fileserver.contoso.com -Port 445 -Protocol TCP
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

	# Begin checking the Private Access application configuration via Microsoft Graph.
	Write-Log "Checking Private Access application configuration..." "INFO"
	try
    {
		$appResult = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/beta/applications?`$select=displayName,appId,id,tags&`$filter=appid eq '$AppId'"
	}
	catch
    {
		Write-Log "Failed to retrieve the application via Microsoft Graph: $($_.Exception.Message)" "ERROR"
		if ($PassThru)
        { return $false }
		return
	}
	$application = @($appResult.value)[0]
	if (-not $application)
    {
		Write-Log "No application found with App ID: $AppId." "ERROR"
		if ($PassThru)
        { return $false }
		return
	}

	# Extract the display name of the application for logging purposes.
	$displayName = $application.displayName

	# Check whether the GSA client access is enabled for the application.
	Write-Log "Checking access with Global Secure Access client configuration..." "INFO"
	$isGSAEnabled = @($application.tags) | Where-Object { $_ -match 'IsAccessibleViaZTNAClient' -or $_ -match 'NetworkAccessQuickAccessApplication' }
	if (-not $isGSAEnabled)
    {
		Write-Log "GSA client access is NOT enabled for Private Access application: $displayName." "ERROR"
		Write-Log "Recommended action: Enable the 'Enable access with Global Secure Access client' option under Network Access Properties for '$displayName'." "WARNING"
		if ($PassThru)
        { return $false }
		return
	}
	Write-Log "Access with Global Secure Access client is enabled for '$displayName'." "SUCCESS"

	$segmentParams = @{
		AppId    = $AppId
		FQDNorIP = $FQDNorIP
		Port     = $Port
		Protocol = $Protocol
		PassThru = $true
	}
	if ($AccessToken)
    { $segmentParams.AccessToken = $AccessToken }
	if ($UserPrincipalName)
    { $segmentParams.UserPrincipalName = $UserPrincipalName }
	if (-not (Test-GSAPrivateAccessApplicationSegment @segmentParams))
    {
		if ($PassThru)
        { return $false }
		return
	}

	Write-Log "Checking tunnel establishment for '$displayName'..." "INFO"
	if (-not (Test-GSAPrivateAccessTunnel -FQDNorIP $FQDNorIP -Port $Port -Protocol $Protocol -PassThru))
    {
		if ($PassThru)
        { return $false }
		return
	}

	Write-Log "Test passed: Private Access application '$displayName' (App ID: $AppId) is fully configured and reachable for '$FQDNorIP' on port $Port/$Protocol." "SUCCESS"
	if ($PassThru)
    { return $true }
}

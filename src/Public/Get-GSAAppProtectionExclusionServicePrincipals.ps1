function Get-GSAAppProtectionExclusionServicePrincipals {
    <#
.SYNOPSIS
    Returns the Global Secure Access service principals that should be excluded from App Protection policies.
.DESCRIPTION
    Provides a curated list of known Global Secure Access-related service principals and app IDs used
    when configuring exclusions in App Protection policies. By default, each App ID is validated in the
    current tenant through Microsoft Graph to report existence and current state.
.PARAMETER AccessToken
    A Microsoft Graph access token with Application.Read.All and Directory.Read.All permissions.
    If omitted and ValidateInTenant is true, an interactive Connect-MgGraph sign-in is triggered
    automatically (requires Microsoft.Graph.Authentication), reusing any already-active session.
.PARAMETER AsHashtable
    Returns each entry as a hashtable instead of a PSCustomObject.
.PARAMETER ValidateInTenant
    When true (default), validates each App ID against Microsoft Graph service principals and includes
    tenant state details.
.PARAMETER PassThru
    Also return the result objects to the pipeline. By default the status is only written to the console.
.EXAMPLE
    Get-GSAAppProtectionExclusionServicePrincipals
.EXAMPLE
    Get-GSAAppProtectionExclusionServicePrincipals -PassThru | Format-Table DisplayName, AppId, ExistsInTenant, CurrentState
#>
    [CmdletBinding()]
    param (
        [string]$AccessToken,
        [switch]$AsHashtable,
        [bool]$ValidateInTenant = $true,
        [switch]$PassThru,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel')) { $script:LogLevel = $LogLevel }

    $entries = @(
        @{ DisplayName = 'Global Secure Access Client'; AppId = 'cde6adac-58fd-4b78-8d6d-9beaf1b0d668' },
        @{ DisplayName = 'Internet resources with Global Secure Access'; AppId = '5dc48733-b5df-475c-a49b-fa307ef00853' },
        @{ DisplayName = 'Microsoft apps with Global Secure Access'; AppId = 'c08f52c9-8f03-4558-a0ea-9a4c878cf343' },
        @{ DisplayName = 'ZTNA Policy Service'; AppId = 'b3fa0115-39b3-4bec-8cc6-8c4fcd33e69d' },
        @{ DisplayName = 'ZTNA Policy Service Client'; AppId = 'ca01d00c-bfd6-46d6-ae7d-be5b5267d037' },
        @{ DisplayName = 'ZTNA Policy Service Graph Client'; AppId = '3b80cd3f-61ca-49b0-8d0f-7b6760e08705' }
    )

    Write-Log "Checking Global Secure Access service principals to exclude from App Protection policies..." "INFO"

    foreach ($entry in $entries) {
        $existsInTenant = $null
        $currentState = 'NotValidated'
        $tenantDisplayName = $null
        $tenantObjectId = $null
        $displayNameMatches = $null

        if ($ValidateInTenant) {
            try {
                $encodedFilter = [uri]::EscapeDataString("appId eq '$($entry.AppId)'")
                $uri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$encodedFilter&`$select=id,appId,displayName,accountEnabled,servicePrincipalType"
                $spResult = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri $uri -Scopes @('Application.Read.All', 'Directory.Read.All')
                $sp = @($spResult.value)[0]

                if ($sp) {
                    $existsInTenant = $true
                    $tenantDisplayName = $sp.displayName
                    $tenantObjectId = $sp.id
                    $displayNameMatches = [string]::Equals([string]$entry.DisplayName, [string]$sp.displayName, [System.StringComparison]::OrdinalIgnoreCase)

                    # Graph responses arrive as Hashtable (SDK session) or PSCustomObject (REST) - read either shape
                    $accountEnabled = $null
                    if ($sp -is [System.Collections.IDictionary]) {
                        if ($sp.Contains('accountEnabled')) { $accountEnabled = $sp['accountEnabled'] }
                    }
                    elseif ($sp.PSObject.Properties.Name -contains 'accountEnabled') {
                        $accountEnabled = $sp.accountEnabled
                    }

                    if ($accountEnabled -eq $true) { $currentState = 'Enabled' }
                    elseif ($accountEnabled -eq $false) { $currentState = 'Disabled' }
                    else { $currentState = 'Unknown' }
                }
                else {
                    $existsInTenant = $false
                    $currentState = 'Missing'
                    $displayNameMatches = $false
                }
            }
            catch {
                $existsInTenant = $null
                $currentState = 'ValidationFailed'
                Write-Log "Failed to validate service principal '$($entry.DisplayName)' ($($entry.AppId)) via Microsoft Graph: $_" "ERROR"
            }
        }

        # Emit a colored status line per service principal (green=present/enabled, red=missing/disabled, yellow=other)
        $statusLevel = switch ($currentState) {
            'Enabled' { 'SUCCESS' }
            'Disabled' { 'ERROR' }
            'Missing' { 'ERROR' }
            'ValidationFailed' { 'WARNING' }
            'NotValidated' { 'INFO' }
            default { 'WARNING' }
        }
        Write-Log "$($entry.DisplayName) ($($entry.AppId)) - $currentState" $statusLevel

        if (-not ($PassThru -or $AsHashtable)) { continue }

        if ($AsHashtable) {
            @{
                DisplayName = $entry.DisplayName
                AppId = $entry.AppId
                Category = 'Global Secure Access'
                Usage = 'Exclude from App Protection policy'
                ValidationNote = 'Based on field validation on Windows and iOS as of 2026-08-30.'
                ExistsInTenant = $existsInTenant
                CurrentState = $currentState
                TenantDisplayName = $tenantDisplayName
                TenantObjectId = $tenantObjectId
                DisplayNameMatches = $displayNameMatches
            }
        }
        else {
            [PSCustomObject]@{
                PSTypeName = 'GSAClientDiagnosticsToolkit.AppProtectionExclusionServicePrincipal'
                DisplayName = $entry.DisplayName
                AppId = $entry.AppId
                Category = 'Global Secure Access'
                Usage = 'Exclude from App Protection policy'
                ValidationNote = 'Based on field validation on Windows and iOS as of 2026-08-30.'
                ExistsInTenant = $existsInTenant
                CurrentState = $currentState
                TenantDisplayName = $tenantDisplayName
                TenantObjectId = $tenantObjectId
                DisplayNameMatches = $displayNameMatches
            }
        }
    }
}
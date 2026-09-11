#
# Function: Test-GSAAppRoleAssignment
# Determines whether a user is assigned to an app role, directly or via group membership.
# Example: Test-GSAAppRoleAssignment -AccessToken $token -UserPrincipalName user@contoso.com -AssignmentRequired $true -AssignedUsers $users -AssignedGroupIds $groupIds
#
function Test-GSAAppRoleAssignment {
    param (
        [string]$AccessToken,
        [string]$UserPrincipalName,
        [bool]$AssignmentRequired,
        [object[]]$AssignedUsers,
        [string[]]$AssignedGroupIds
    )

    # Assignment isn't enforced, so every user (including this one) has access
    if (-not $AssignmentRequired) { return $true }

    try {
        $user = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/v1.0/users/$UserPrincipalName"
    }
    catch {
        Write-Log "Failed to resolve user '$UserPrincipalName' via Microsoft Graph: $($_.Exception.Message)" "ERROR"
        return $false
    }
    if (-not $user -or -not $user.id) {
        Write-Log "Could not resolve user '$UserPrincipalName' via Microsoft Graph." "ERROR"
        return $false
    }

    if (@($AssignedUsers) | Where-Object { $_.principalId -eq $user.id }) {
        return $true
    }

    if (-not $AssignedGroupIds -or @($AssignedGroupIds).Count -eq 0) {
        return $false
    }

    try {
        $body = @{ groupIds = @($AssignedGroupIds) }
        $groups = Invoke-GSAGraphRequest -AccessToken $AccessToken -Uri "https://graph.microsoft.com/beta/users/$UserPrincipalName/checkMemberGroups" -Method "POST" -Body $body
    }
    catch {
        Write-Log "Failed to check group membership for '$UserPrincipalName' via Microsoft Graph: $($_.Exception.Message)" "ERROR"
        return $false
    }

    return (@($groups.value).Count -gt 0)
}

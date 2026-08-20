#
# Function: Get-GSACurrentUserUPN
# Returns the UPN of the currently signed-in Windows user (falls back to $null on failure).
# Example: Get-GSACurrentUserUPN
#
function Get-GSACurrentUserUPN {
    try {
        $upn = whoami /upn 2>$null
        if ([string]::IsNullOrWhiteSpace($upn)) { return $null }
        return $upn.Trim()
    }
    catch {
        return $null
    }
}

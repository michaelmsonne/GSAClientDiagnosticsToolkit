# ---------------------------------------------
# Function: Test-IsElevated checks for admin rights
# ---------------------------------------------
function Test-IsElevated {
    return ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

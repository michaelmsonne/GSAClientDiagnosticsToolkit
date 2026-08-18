#
# Function: Test-GSAServiceStatus
# Checks that all required Global Secure Access Windows services are running.
#
function Test-GSAServiceStatus {
<#
.SYNOPSIS
    Verifies that all required Global Secure Access Windows services are running.
.DESCRIPTION
    Checks the following services:
        - GlobalSecureAccessTunnelingService      (Tunneling)
        - GlobalSecureAccessClientManagerService  (Client Manager)
        - GlobalSecureAccessEngineService         (Engine)
        - GlobalSecureAccessDriver                (Driver)
        - GlobalSecureAccessPolicyRetrieverService / GlobalSecureAccessForwardingProfileService (Forwarding Profile)
#>
    $allTestsPassed = $true

    # Fixed-name services that must each be Running
    $services = @(
        @{ Name = 'GlobalSecureAccessTunnelingService';     DisplayName = 'Tunneling Service' }
        @{ Name = 'GlobalSecureAccessClientManagerService'; DisplayName = 'Client Manager Service' }
        @{ Name = 'GlobalSecureAccessEngineService';        DisplayName = 'Engine Service' }
        @{ Name = 'GlobalSecureAccessDriver';               DisplayName = 'Driver Service' }
    )

    foreach ($svc in $services) {
        Write-Log "Checking $($svc.DisplayName) ($($svc.Name))..." "INFO"
        $status = (Get-Service -Name $svc.Name -ErrorAction SilentlyContinue).Status
        if ($status -eq 'Running') {
            Write-Log "$($svc.DisplayName) is running." "SUCCESS"
        } else {
            Write-Log "$($svc.DisplayName) ($($svc.Name)) is not running (Status: $status). Ensure the service is started." "ERROR"
            $allTestsPassed = $false
        }
    }

    # Forwarding Profile Service — either the old or new service name may be present depending on client version
    Write-Log "Checking Forwarding Profile Service..." "INFO"
    $fpStatus  = (Get-Service -Name 'GlobalSecureAccessPolicyRetrieverService'  -ErrorAction SilentlyContinue).Status
    $fpStatus2 = (Get-Service -Name 'GlobalSecureAccessForwardingProfileService' -ErrorAction SilentlyContinue).Status
    if ($fpStatus -eq 'Running' -or $fpStatus2 -eq 'Running') {
        Write-Log "Forwarding Profile Service is running." "SUCCESS"
    } else {
        Write-Log "Forwarding Profile Service is not running. Ensure GlobalSecureAccessForwardingProfileService (or GlobalSecureAccessPolicyRetrieverService) is started." "ERROR"
        $allTestsPassed = $false
    }

    return $allTestsPassed
}

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
        $svcObj = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($svcObj.Status -eq 'Running') {
            Write-Log "$($svc.DisplayName) is running." "SUCCESS"
            if ($script:LogLevel -eq "DEBUG") {
                Write-Log "  StartType: $($svcObj.StartType)" "DEBUG"
            }
        } else {
            Write-Log "$($svc.DisplayName) ($($svc.Name)) is not running (Status: $($svcObj.Status)). Ensure the service is started." "ERROR"
            $allTestsPassed = $false
        }
    }

    # Forwarding Profile Service - either the old or new service name may be present depending on client version
    Write-Log "Checking Forwarding Profile Service..." "INFO"
    $fpSvc  = Get-Service -Name 'GlobalSecureAccessPolicyRetrieverService'  -ErrorAction SilentlyContinue
    $fpSvc2 = Get-Service -Name 'GlobalSecureAccessForwardingProfileService' -ErrorAction SilentlyContinue
    if ($fpSvc.Status -eq 'Running' -or $fpSvc2.Status -eq 'Running') {
        Write-Log "Forwarding Profile Service is running." "SUCCESS"
        if ($script:LogLevel -eq "DEBUG") {
            $running = if ($fpSvc.Status -eq 'Running') { $fpSvc } else { $fpSvc2 }
            Write-Log "  Name: $($running.Name), StartType: $($running.StartType)" "DEBUG"
        }
    } else {
        Write-Log "Forwarding Profile Service is not running. Ensure GlobalSecureAccessForwardingProfileService (or GlobalSecureAccessPolicyRetrieverService) is started." "ERROR"
        $allTestsPassed = $false
    }

    return $allTestsPassed
}

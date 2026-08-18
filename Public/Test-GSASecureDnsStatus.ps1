#
# Function: Test-GSASecureDnsStatus
# Checks whether Secure DNS (DoH) is disabled in Chrome and Edge.
# GSA uses WFP to intercept DNS queries; DoH bypasses WFP so FQDN-based traffic
# rules cannot be matched and traffic is not tunneled.
#
function Test-GSASecureDnsStatus {
<#
.SYNOPSIS
    Verifies that Secure DNS (DNS-over-HTTPS) is disabled in Microsoft Edge and Google Chrome.
.DESCRIPTION
    GSA intercepts DNS queries at the WFP layer to match FQDN-based forwarding rules.
    When DoH is active, DNS bypasses WFP and GSA cannot identify the destination,
    so traffic is not tunneled. Checks HKLM and HKCU policy registry keys for both browsers.
    Disable DoH via Group Policy (DnsOverHttpsMode = off) or in browser settings.
#>
    $allPassed = $true

    $browsers = @(
        @{ Name = 'Microsoft Edge'; Paths = @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKCU:\SOFTWARE\Policies\Microsoft\Edge') }
        @{ Name = 'Google Chrome';  Paths = @('HKLM:\SOFTWARE\Policies\Google\Chrome',  'HKCU:\SOFTWARE\Policies\Google\Chrome') }
    )

    Write-Log "Checking Secure DNS (DoH) policy settings - GSA requires DoH to be disabled..." "INFO"

    foreach ($browser in $browsers) {
        $dohFound = $false
        foreach ($path in $browser.Paths) {
            $dohMode = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).DnsOverHttpsMode
            if ($dohMode -and $dohMode -ne "off") {
                Write-Log "$($browser.Name): Secure DNS is enabled (DnsOverHttpsMode = '$dohMode' at $path). GSA cannot acquire FQDN-based traffic when DoH is active. Set DnsOverHttpsMode to 'off' via Group Policy or disable DoH in the browser." "WARNING"
                $dohFound = $true
                break
            }
        }
        if (-not $dohFound) {
            Write-Log "$($browser.Name): Secure DNS (DoH) is not enforced or is set to 'off'." "SUCCESS"
        }
    }

    return $allPassed
}

#
# Function: Test-GSAVpnSplitDnsInteroperability
# Detects a known interoperability scenario where Cisco VPN + GSA NRPT/private DNS can
# produce REFUSED DNS answers for a private suffix unless Cisco allows source 6.6.0.0/16.
#
function Test-GSAVpnSplitDnsInteroperability {
    <#
.SYNOPSIS
	Detects the Cisco VPN + GSA private DNS split-DNS REFUSED scenario for a target DNS suffix.
.DESCRIPTION
	Checks for an active Cisco VPN adapter, verifies there is an NRPT rule that applies to the
	specified DNS suffix, and performs a DNS lookup for a probe hostname under that suffix.
	If the lookup fails with REFUSED while Cisco VPN is active, this matches a known scenario
	where Cisco split-DNS/ACL drops requests sourced from the GSA synthetic 6.6.0.0/16 range.
	Recommended fix in that case: add 6.6.0.0/16 to the Cisco split-DNS extended ACL source list.
	This is a local/offline client-side check and does not call Microsoft Graph.
.PARAMETER DnsSuffix
	Target DNS suffix/domain to test (for example: mydomain.com).
.PARAMETER ProbeHostLabel
	Hostname label used for the probe query under DnsSuffix. Defaults to _gsa_vpn_interop_probe.
	Using a dedicated probe label avoids relying on a specific production host record.
.PARAMETER CiscoAdapterPattern
	Regex pattern used to identify Cisco VPN adapters by Name/InterfaceDescription.
	Default matches Cisco AnyConnect and Cisco Secure Client.
.PARAMETER PassThru
    Stores the pass/fail result for orchestration without writing boolean output to the pipeline.
    By default nothing is returned - only logged.
.EXAMPLE
	Test-GSAVpnSplitDnsInteroperability -DnsSuffix mydomain.com
.EXAMPLE
	Test-GSAVpnSplitDnsInteroperability -DnsSuffix mydomain.com -PassThru
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$DnsSuffix,
        [string]$ProbeHostLabel = '_gsa_vpn_interop_probe',
        [string]$CiscoAdapterPattern = 'Cisco AnyConnect|Cisco Secure Client',
        [switch]$PassThru,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$LogLevel
    )

    if ($PSBoundParameters.ContainsKey('LogLevel'))
    { $script:LogLevel = $LogLevel }

    $normalizedSuffix = $DnsSuffix.Trim().TrimStart('.')
    $probeFqdn = "$ProbeHostLabel.$normalizedSuffix"
    $passed = $true

    Write-Log "Checking Cisco VPN + GSA split-DNS interoperability for suffix '$normalizedSuffix'..." "INFO"

    $ciscoAdapters = @(
        Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Status -eq 'Up' -and (
                $_.Name -match $CiscoAdapterPattern -or
                $_.InterfaceDescription -match $CiscoAdapterPattern
            )
        }
    )

    if ($ciscoAdapters.Count -eq 0) {
        Write-Log "No active Cisco VPN adapter detected. Scenario is not currently applicable." "SUCCESS"
        if ($PassThru)
        { $script:_testResult = $true }
        return
    }

    Write-Log "Detected active Cisco VPN adapter(s): $($ciscoAdapters.Name -join ', ')." "INFO"

    $nrptRules = @()
    try {
        $nrptRules = @(Get-DnsClientNrptRule -ErrorAction Stop)
    }
    catch {
        Write-Log "Could not read NRPT rules: $($_.Exception.Message)." "WARNING"
        Write-Log "This check is inconclusive without NRPT visibility." "WARNING"
        if ($PassThru)
        { $script:_testResult = $true }
        return
    }

    $matchingNrptRules = @()
    foreach ($rule in $nrptRules) {
        foreach ($namespace in @($rule.Namespace | Where-Object { $_ })) {
            $normalizedNamespace = $namespace.Trim().TrimStart('*').TrimStart('.')
            if ([string]::IsNullOrWhiteSpace($normalizedNamespace))
            { continue }

            if (
                $normalizedSuffix -ieq $normalizedNamespace -or
                $normalizedSuffix -ilike "*.$normalizedNamespace"
            ) {
                $matchingNrptRules += $rule
                break
            }
        }
    }

    if ($matchingNrptRules.Count -eq 0) {
        Write-Log "No NRPT rules apply to '$normalizedSuffix'. This specific scenario was not detected." "INFO"
        if ($PassThru)
        { $script:_testResult = $true }
        return
    }

    Write-Log "Found $($matchingNrptRules.Count) NRPT rule(s) matching '$normalizedSuffix'." "INFO"
    Write-Log "Testing DNS query for probe host '$probeFqdn'..." "INFO"

    try {
        [void](Resolve-DnsName -Name $probeFqdn -ErrorAction Stop)
        Write-Log "Probe lookup succeeded. The Cisco/GSA split-DNS REFUSED scenario was not reproduced." "SUCCESS"
    }
    catch {
        $errorMessage = $_.Exception.Message

        if ($errorMessage -match 'REFUSED|query refused|DNS_ERROR_RCODE_REFUSED') {
            Write-Log "DNS lookup for '$probeFqdn' failed with REFUSED while Cisco VPN and matching NRPT rule(s) are active." "ERROR"
            Write-Log "Likely scenario detected: Cisco split-DNS/ACL is dropping DNS requests sourced from GSA synthetic range 6.6.0.0/16." "WARNING"
            Write-Log "Recommended action: In Cisco VPN split-DNS + extended ACL, add source network 6.6.0.0/16 so these DNS queries are allowed." "WARNING"
            $passed = $false
        }
        elseif ($errorMessage -match 'DNS name does not exist|NXDOMAIN|Non-existent domain') {
            # NXDOMAIN still indicates the DNS path is functioning; this probe name may simply not exist.
            Write-Log "Probe lookup returned NXDOMAIN (expected for a synthetic probe label). DNS path is reachable; scenario not reproduced." "SUCCESS"
        }
        else {
            Write-Log "Probe lookup for '$probeFqdn' failed with a non-REFUSED error: $errorMessage" "WARNING"
            Write-Log "Result is inconclusive for the Cisco/GSA split-DNS REFUSED scenario." "WARNING"
        }
    }

    if ($PassThru)
    { $script:_testResult = $passed }
}

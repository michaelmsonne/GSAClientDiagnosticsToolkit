#====================================================================================================================== 
# THIS CODE-SAMPLE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT 
# LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
#
# This sample is not supported under any Microsoft standard support program or service. The code sample is provided 
# AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, 
# any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the 
# use or performance of the sample and documentation remains with you. In no event shall Microsoft, its authors, or 
# anyone else involved in the creation, production, or delivery of the script be liable for any damages whatsoever 
# (including, without limitation, damages for loss of business profits, business interruption, loss of business 
# information, or other pecuniary loss) arising out of  the use of or inability to use the sample or documentation, 
# even if Microsoft has been advised of the possibility of such damages.
#====================================================================================================================== 

<#
.SYNOPSIS
    Runs connectivity, proxy, health probes and mTLS checks for the GSA Client.    

.DESCRIPTION
    The Script will check the following: 
        1. Active network interfaces with default routes
        2. Reachability of specified websites
        3. Reachability of specified DNS servers
        4. Read the GSA JSON from the registry
        5. Extract Edge Addresses from JSON
        6. Test DNS resolution for each FQDN
        7. Test TLS connectivity to each FQDN
        8. Test mTLS connectivity to each FQDN
        9. Test gRPC proxy settings
        10. Test system web proxy settings
        11. Test for transparent proxy detection via HTTP headers
        12. Test for authenticating proxy detection via HTTP 407 response
        13. Test Entra ID connectivity   
        15. Test DiagnosticUri connectivity

.PARAMETER LogLevel
    Specifies the verbosity of logging output. Valid values: ERROR, WARNING, INFO, DEBUG

    If etc. set to DEBUG, all messages will be logged including certificate details for endpoints. (usefull for etc. debugging TLS inspection issues)

.EXAMPLE
    .\GSA-Diagnostics.ps1 -LogLevel DEBUG

.EXAMPLE
    .\GSA-Diagnostics.ps1 -LogLevel ERROR

.NOTES
    Author: GSA CxE Team (Microsoft - tdetzner) - optimized, new features and revised by Michael Morten Sonne
    Date/Version: See $ScriptVer

#>

# ---------------------------------------------
# Configuration (Uses Parameters)
# ---------------------------------------------
param (
    [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
    [string]$LogLevel = "INFO",
    [string]$BasePath = (Get-Location),  # Use the current directory as the base directory
    [string]$LogFileName = "GSAClientConnectivityChecker.log"
)

$ScriptVer = "09April2025"

# Define a global variables 
# Globals for the GSA registry path
$Global:GSAFwdProfileRegistryPath = "HKLM:\SOFTWARE\Microsoft\Global Secure Access Client"

# Define the full paths for the JSON (optional for now) and log files
# the paths can be optional, we will mainly use the registry to get the JSON data
# $JsonFilePath = Join-Path -Path $BasePath -ChildPath $JsonFileName
$LogFilePath = Join-Path -Path $BasePath -ChildPath $LogFileName

# ---------------------------------------------
# Function: Test-IsElevated checks for admin rights
# ---------------------------------------------
function Test-IsElevated {
    return ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Ensure directory exists
try {
    if (-Not (Test-Path $BasePath)) {
        New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
    }
} catch {
    Write-Log -Message "Failed to create directory at path: $BasePath. Error: $_" -Level "ERROR"
    throw
}

# global lock Object used for logging thread safety
if (-not $Global:LogLockObject) {
    $Global:LogLockObject = New-Object System.Object
}

# 
# Function: Logging with Console Output (thread safe)
# 
# This function will log messages to the console and a log file.
# It uses a global lock object to ensure thread safety.
# Input parameters:
# - Message: The message to log.
# - Level: The log level (ERROR, WARNING, INFO, DEBUG, SUCCESS). Default is INFO.
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $levels = @("ERROR", "WARNING", "INFO", "DEBUG")
    $currentIndex = $levels.IndexOf($LogLevel.ToUpper())
    $messageIndex = $levels.IndexOf($Level.ToUpper())

    [System.Threading.Monitor]::Enter($Global:LogLockObject)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$level] $message"

        if ($messageIndex -le $currentIndex -or $Level -eq "SUCCESS") {
            $color = switch ($Level) {
                "ERROR" { "Red" }
                "WARNING" { "Yellow" }
                "INFO" { "Gray" }
                "DEBUG" { "Cyan" }
                "SUCCESS" { "Green" }
            }
            Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
        }

        # Use a file stream to write to the log file to avoid file access conflicts
        $fileStream = [System.IO.File]::Open($LogFilePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $streamWriter = New-Object System.IO.StreamWriter($fileStream)
        try {
            $streamWriter.WriteLine($logMessage)
        } 
        finally {
            $streamWriter.Close()
            $fileStream.Close()
        }
    }   
    finally {
        [System.Threading.Monitor]::Exit($Global:LogLockObject)
    }
}

<#
# ---------------------------------------------
# Function: Read & Parse JSON from a file
# ---------------------------------------------
function Get-PolicyJsonFromFile {
    param ([string]$jsonFilePath)

    if (-Not (Test-Path $jsonFilePath)) {
        Write-Log "JSON file not found: $jsonFilePath" "ERROR"
        return $null
    }

    try {
        $jsonContent = Get-Content $jsonFilePath -Raw | ConvertFrom-Json
        Write-Log "Successfully read JSON file."
        return $jsonContent
    } catch {
        Write-Log "Error parsing JSON file: $_" "ERROR"
        return $null
    }
}
#>

# 
# Function: Load the ForwardingProfile from Registry
# 
function Get-JsonFromRegistry {
    param (
        [string]$ValueName = "ForwardingProfile"  # Adjust if the JSON is stored under a different value name
    )

    try {
        # Read the JSON string from the registry
        $jsonString = Get-ItemPropertyValue -Path $Global:GSAFwdProfileRegistryPath -Name $ValueName -ErrorAction Stop
        if (-Not $jsonString) {
            Write-Log -Message "No JSON data found at registry path: $Global:GSAFwdProfileRegistryPath" -Level Error
            return $null
        }
        $jsonContent = $jsonString | ConvertFrom-Json
        Write-Log -Message "Successfully read JSON data from registry path: $Global:GSAFwdProfileRegistryPath" -Level Info
        return $jsonContent
    } catch {
        Write-Log -Message "Failed to read JSON from registry: $_" -Level Error
        return $null
    }
}

# 
# Function: Extract Edge Addresses from JSON
# 
function Get-GSAMainEndpoints {
    param ([object]$jsonContent)

    if (-Not $jsonContent.policy.channels) {
        Write-Log "No channels found in JSON file." "WARNING"
        return @()
    }

    $channelEndpoints = @()

    # Iterate through each channel in the JSON content
    foreach ($channel in $jsonContent.policy.channels) {
        $edges = @()
        # Check if the channel has edges settings
        $channelName = $channel.name
        $diagnosticUri = $channel.diagnosticUri

        # Check if the channel has edges settings and extract edge addresses
        if ($channel.edgesSettings.primaryEdges) {
            foreach ($edge in $channel.edgesSettings.primaryEdges) {
                $edges += $edge.edgeAddress
            }
        }

        if ($channel.edgesSettings.secondaryEdges) {
            foreach ($edge in $channel.edgesSettings.secondaryEdges) {
                $edges += $edge.edgeAddress
            }
        }

        # Create an object for each channel
        $channelEndpoints += [PSCustomObject]@{
            ChannelName   = $channelName
            EdgeAddresses = $edges
            DiagnosticUri = $diagnosticUri
        }
    } 

    Write-Log "Extracted $($channelEndpoints.Count) channel entries with endpoint data."

    return $channelEndpoints
}

# 
# Function: Save Edge Addresses to File
# 
function Save-EdgeAddresses {
    param (
        [string[]]$fqdnList,
        [string]$filePath
    )

    try {
        if (-not $fqdnList -or $fqdnList.Count -eq 0) {
            Write-Log "No FQDNs provided to save." "ERROR"
            return
        }

        if (-not $filePath) {
            Write-Log "File path is not specified." "ERROR"
            return
        }

        # Ensure the directory for the file path exists
        $directory = Split-Path -Path $filePath -Parent
        if (-not (Test-Path $directory)) {
            try {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
                Write-Log "Created directory: $directory" "INFO"
            } catch {
                Write-Log "Failed to create directory: $directory. Error: $_" "ERROR"
                return
            }
        }

        # Save the FQDN list to the file
        $fqdnList | Out-File -Encoding utf8 $filePath -Force
        Write-Log "Edge addresses saved to: $filePath" "SUCCESS"
    } catch {
        Write-Log "Failed to save edge addresses to $filePath. Error: $_" "ERROR"
    }
}

#
# Function: Test-UDPPort 
# helper code to test UDP port connectivity
# 
function Test-UDPPort {
    param (
        [string]$IPAddress,
        [int]$Port = 53,
        [int]$Timeout = 5000
    )

    try {
        $udpClient = [System.Net.Sockets.UdpClient]::new()
        $udpClient.Connect($IPAddress, $Port)
        Write-Log -Message "Testing UDP connectivity to $IPAddress on port $Port" -Level "INFO"

        # Construct a simple DNS query for nxdomain.com to minimize data transmission
        $query = [byte[]](0xAA, 0xAA, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x6e, 0x78, 0x64, 0x6f, 0x6d, 0x61, 0x69, 0x6e, 0x03, 0x63, 0x6f, 0x6d, 0x00, 0x00, 0x01, 0x00, 0x00)

        $udpClient.Send($query, $query.Length)

        # blocking receive until we get a response or timeout
        # $response = $udpClient.Receive([ref]$IPAddress, [ref]$Port)
        # $udpClient.Close()
        
        $receiveTask = $udpClient.ReceiveAsync()
        if ($receiveTask.Wait($Timeout)) {
            $receiveTask.Result | Out-Null
            $udpClient.Close()
            return $true
        } 
        
        else {
            $udpClient.Close()
            return $false
        }        
    } 
    catch {
        return $false
    }
}

# 
# Function: Test-InternetConnectivity checks base connectivity
# with the following tests:
# 1. Active network interfaces with default routes
# 2. Reachability of specified websites
# 3. Reachability of specified DNS servers
# 
function Test-InternetConnectivity {
    param (
        [string[]]$Websites = @("www.google.com", "www.microsoft.com"),
        [string[]]$DnsServers = @("1.1.1.1", "8.8.8.8", "9.9.9.9")
    )

    # Set default state for tests
    $allTestsPassed = $true

    # Check for active network interfaces with default routes
    $defaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne "::" }
    if ($defaultRoutes) {
        Write-Log "Active network interfaces with default routes detected." "INFO"
    }
    else {
        Write-Log "No active network interfaces with default routes found." "ERROR"
        $allTestsPassed = $false
    }

    # Test reachability of specified websites
    foreach ($site in $Websites) {
        $testResult = Test-NetConnection -ComputerName $site -InformationLevel Quiet
        if ($testResult) {
            Write-Log "Website $site is reachable." "INFO"
        } 
        else {
            Write-Log "Website $site is not reachable." "ERROR"
            $allTestsPassed = $false
        }
    }

    # Test reachability of specified DNS servers over TCP and UDP
    foreach ($dns in $DnsServers) 
    {
        # UDP Check
        $udpTestResult = Test-UDPPort -IPAddress $dns -Timeout ($TimeoutSec)
        if ($udpTestResult) {
            Write-Log "DNS server $dns is reachable on UDP port 53." "INFO"
        } 
        else {
            Write-Log "DNS server $dns is not reachable on UDP port 53." "ERROR"
            $allTestsPassed = $false
        }

        <# TCP Check skipping for now
        # TCP Check are optional, default DNS is over UDP
        $tcpTestResult = Test-NetConnection -ComputerName $dns -Port 53 -InformationLevel Quiet
        if ($tcpTestResult) {
            Write-Log "DNS server $dns is reachable on TCP port 53." "INFO"
        } 
        else 
        {
            Write-Log "DNS server $dns is not reachable on TCP port 53." "WARNING"
        }      
        # #>
    }   

    return $allTestsPassed
}

# 
# Function: Get-DnsChain
# Recursively retrieves the CNAME chain for a given FQDN.
# 
function Get-DnsChain {
    param (
        [string]$fqdn,
        [int]$depth = 0,
        [hashtable]$visited = @{}
    )

    # Limit recursion to avoid infinite loops (max 10 levels)
    if ($depth -ge 10) {
        Write-Log "Recursion limit reached for $fqdn" "WARNING"
        return @()
    }

    # Avoid processing the same FQDN more than once.
    if ($visited.ContainsKey($fqdn)) { return @() }
    $visited[$fqdn] = $true

    $chain = @()

    try {
        $records = Resolve-DnsName -Name $fqdn -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to resolve $fqdn when chasing CNAMEs: $_" "ERROR"
        return @()
    }

    # Look for CNAME records in the result.
    $cnameRecords = $records | Where-Object { $_.QueryType -eq "CNAME" }
    foreach ($record in $cnameRecords) {
        $target = $record.NameHost
        # Skip self-referential CNAMEs (injected by GSA synthetic DNS) and already-visited targets
        if ([string]::IsNullOrEmpty($target) -or $target -eq $fqdn -or $visited.ContainsKey($target)) { continue }
        # Append the CNAME target.
        $chain += $target
        # Recursively check for additional CNAMEs.
        $childChain = Get-DnsChain -fqdn $target -depth ($depth + 1) -visited $visited
        if ($childChain) {
            $chain += $childChain
        }
    }
    return $chain
}

# 
# Function: Test-DnsResolution 
# This function performs DNS resolution for each FQDN, outputs IP addresses, and
# logs the CNAME chain if present.
# 
function Test-DnsResolution {
    param (
        [string[]]$fqdnList
    )

    $allTestsPassed = $true

    foreach ($fqdn in $fqdnList) {
        Write-Log "Checking DNS resolution for: $fqdn" "INFO"

        try {
            # Resolve DNS for all record types
            $records = Resolve-DnsName -Name $fqdn -NoHostsFile -ErrorAction Stop

            # Extract A and AAAA records (IP addresses)
            $ipAddresses = $records | Where-Object { $_.QueryType -eq "A" -or $_.QueryType -eq "AAAA" } | 
                           Select-Object -ExpandProperty IPAddress -Unique
            if ($ipAddresses) {
                Write-Log "DNS resolution for $fqdn returned IP addresses: $($ipAddresses -join ', ')" "SUCCESS"
            } else {
                Write-Log "DNS resolution for $fqdn did not return any A/AAAA records." "WARNING"
            }

            # Retrieve the CNAME chain (if any)
            $cnameChain = Get-DnsChain -fqdn $fqdn
            if ($cnameChain.Count -gt 0) {
                Write-Log "CNAME chain for $fqdn ($($cnameChain.Count) hop(s)):" "INFO"
                Write-Log "  $fqdn" "INFO"
                foreach ($hop in $cnameChain) {
                    Write-Log "  -> $hop" "INFO"
                }
            } else {
                Write-Log "No CNAME records found for $fqdn." "INFO"
            }
        } catch {
            Write-Log "DNS resolution for $fqdn failed: $_" "ERROR"
            $allTestsPassed = $false
        }
    }
    return $allTestsPassed
}

# 
# Function: Test TLS Connectivity to Edge Addresses
# 
function Test-TLSConnection {
    param (
        [string[]]$fqdnList,
        [int]$port = 443
    )

    $allTestsPassed = $true

    foreach ($fqdn in $fqdnList) {
        Write-Log "Checking connection to: $fqdn on port $port" "INFO"

        try {
            # Create and connect the TCP client
            $tcpClient = [System.Net.Sockets.TcpClient]::new($fqdn, $port)
            Write-Log "TCP connection successful to $fqdn" "SUCCESS"

            # Create and authenticate the SSL stream
            $sslStream = [System.Net.Security.SslStream]::new($tcpClient.GetStream(), $false, { $true })
            try {
                $sslStream.AuthenticateAsClient($fqdn)
                Write-Log "TLS handshake successful with $fqdn" "SUCCESS"

                # Log certificate details if in DEBUG mode
                if ($LogLevel -eq "DEBUG") {
                    $remoteCertificate = $sslStream.RemoteCertificate
                    if ($remoteCertificate) {
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $remoteCertificate
                        Write-Log "TLS Certificate Details for $fqdn :" "DEBUG"
                        Write-Log "  Subject: $($cert.Subject)" "DEBUG"
                        Write-Log "  Issuer: $($cert.Issuer)" "DEBUG"
                        Write-Log "  Valid From: $($cert.NotBefore)" "DEBUG"
                        Write-Log "  Valid Until: $($cert.NotAfter)" "DEBUG"
                        Write-Log "  Thumbprint: $($cert.Thumbprint)" "DEBUG"
                    } else {
                        Write-Log "No TLS certificate information available for $fqdn." "DEBUG"
                    }
                }
            } catch {
                Write-Log "TLS handshake failed with $fqdn : $_" "ERROR"
                $allTestsPassed = $false
            } finally {
                $sslStream.Dispose()
            }
        } catch {
            Write-Log "TCP connection failed to $fqdn : $_" "ERROR"
            $allTestsPassed = $false
        } finally {
            if ($tcpClient) { $tcpClient.Close() }
        }
    }

    return $allTestsPassed
}

# 
# Function: Test-mTLSConnection
# this function will Test mTLS connectivity to the Edge Addresses
# 
function Test-mTLSConnection {
    param (
        [string[]]$fqdnList,
        [int]$port = 443        
    )

    $allTestsPassed = $true
    $warningsLogged = $false
    $runningElevated = Test-IsElevated

    if (-not ($runningElevated)) {
        Write-Log "This script is not running elevated" "WARNING"
        Write-Log "mTLS checks will most likely fail, due to missing permissions on the computer's mTLS certificate private key(s)" "WARNING"
        $warningsLogged = $true
    }

    # Retrieve mTLS-capable certificates from the LocalMachine "My" store.
    $mtlsCertificates = Get-mTLSCertificates

    if ($mtlsCertificates.Count -eq 0) {
        Write-Log "No mTLS-capable certificates were found." "WARNING"
        Write-Log "This could be normal, if the tenant is not yet onboarded to mTLS" "WARNING"
        $warningsLogged = $true

        # Skip the test since no certificates are available
        Write-Log "Skipping mTLS connection attempts due to lack of mTLS-capable certificates." "INFO"
        return [PSCustomObject]@{
            Passed   = $true
            Warnings = 1
        }
    } else {
        Write-Log "Found $($mtlsCertificates.Count) mTLS-capable GSA client certificate(s)." "SUCCESS"
    }

    foreach ($fqdn in $fqdnList) {
        Write-Log "Attempting mTLS connection to: $fqdn on port $port" "INFO"

        foreach ($ClientCert in $mtlsCertificates) {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            try {
                $tcpClient.Connect($fqdn, $port)
                Write-Log "TCP connection successful to $fqdn" "SUCCESS"
            } catch {
                Write-Log "TCP connection failed to $fqdn : $_" "ERROR"
                $allTestsPassed = $false
                continue
            }

            $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, ({ $true }))
            try {
                # Prepare client certificate collection if provided.
                $clientCerts = New-Object System.Security.Cryptography.X509Certificates.X509CertificateCollection
                if ($ClientCert) { [void]$clientCerts.Add($ClientCert) }
                # Attempt the mTLS handshake using TLS 1.2
                $sslStream.AuthenticateAsClient($fqdn, $clientCerts, [System.Security.Authentication.SslProtocols]::Tls12, $false)
                $ismTLSdone = $sslStream.Ismutuallyauthenticated
                Write-Log "mTLS handshake succeeded for $fqdn with certificate $($ClientCert.Subject) mTLS: $ismTLSdone" "SUCCESS"
            } catch {
                if (-not ($runningElevated)) {
                    Write-Log "mTLS handshake failed for $fqdn " "WARNING"
                    Write-Log "Expected due to not running elevated. Run again with elevation" "WARNING"
                    $warningsLogged = $true
                } else {
                    Write-Log "mTLS handshake failed for $fqdn with certificate $($ClientCert.Subject) : $_" "ERROR"
                    $allTestsPassed = $false
                }
            } finally {
                $sslStream.Dispose()
                $tcpClient.Close()
            }
        }
    }

    # Determine the final result
    if (-not $allTestsPassed) {
        Write-Log "One or more mTLS connection attempts failed." "WARNING"
        $warningsLogged = $true
    }

    return [PSCustomObject]@{
        Passed   = $allTestsPassed
        Warnings = if ($warningsLogged) { 1 } else { 0 }
    }
}

# 
# Function: Get-mTLSCertificates enumarates 
# the certificates in the LocalMachine "My" store
# 
function Get-mTLSCertificates {
    param (
        [string]$StoreName = "My",
        [string]$StoreLocation = "LocalMachine"
    )

    $mtlsCerts = @()
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, $StoreLocation)

    try {
        $store.Open("ReadOnly")
        # Filter certificates that have a private key and are not expired
        $certs = $store.Certificates | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) }
        foreach ($cert in $certs) {
            try {
                # Get all EKU extensions for the certificate
                $ekuExtensions = $cert.Extensions | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] }
                $clientAuthFound = $false
                foreach ($extension in $ekuExtensions) 
                {
                    # look for Client Auth certs only ...
                    foreach ($usage in $extension.EnhancedKeyUsages) 
                    {
                        if ($usage.Value -eq "1.3.6.1.5.5.7.3.2") {
                            $clientAuthFound = $true
                            break
                        }
                    }
                    if ($clientAuthFound) { break }
                }
                if ($clientAuthFound) 
                {
                    # we found a capable mTLS certificate
                    # only add the certs, which have tenant.gsa.client in the subject
                    if ($cert.Subject -match "tenant.gsa.client") 
                    {
                        $mtlsCerts += $cert
                        Write-Log "Certificate accepted for mTLS: Subject=$($cert.Subject), Thumbprint=$($cert.Thumbprint) and with the GSA specific Subject name" "SUCCESS"
                    }
                }
            } catch {
                Write-Log "Error processing certificate $($cert.Subject): $_" "ERROR"
            }
        }
        return $mtlsCerts
    } catch {
        Write-Log "Error retrieving certificates from store: $_" "ERROR"
        return @()
    }
    finally {
        $store.Close()
    }
}

#
# Function: Test-GSAPrimaryRefreshToken
# Checks whether a Primary Refresh Token (PRT) is present (AzureAdPrt: YES).
# Without PRT the GSA client cannot authenticate with Entra ID.
#
function Test-GSAPrimaryRefreshToken {
    Write-Log "Checking Primary Refresh Token (PRT) status via dsregcmd..." "INFO"
    try {
        $dsregOutput = dsregcmd /status 2>&1
        $prtPresent  = ($dsregOutput | Select-String -Pattern 'AzureAdPrt' -SimpleMatch) -match 'YES'
        if ($prtPresent) {
            Write-Log "Primary Refresh Token (AzureAdPrt) is present - device can authenticate with Entra ID." "SUCCESS"
            if ($LogLevel -eq "DEBUG") {
                $prtTime = $dsregOutput | Select-String -Pattern '^\s*AzureAdPrtUpdateTime\s*:' | Select-Object -First 1
                if ($prtTime) { Write-Log "  AzureAdPrtUpdateTime : $(($prtTime.ToString() -split ':', 2)[1].Trim())" "DEBUG" }
            }
            return $true
        } else {
            Write-Log "Primary Refresh Token (AzureAdPrt) is NOT present. The GSA client cannot authenticate. Ensure the device is Entra Joined, has network connectivity to login.microsoftonline.com, and no Conditional Access policy is blocking sign-in." "ERROR"
            return $false
        }
    } catch {
        Write-Log "Failed to check PRT status via dsregcmd: $_" "ERROR"
        return $false
    }
}

#
# Function: Test-GSAForwardingProfileTimestamp
# Checks the ForwardingProfileTimestamp registry value age to detect stale profiles.
#
function Test-GSAForwardingProfileTimestamp {
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Global Secure Access Client"
    $valueName    = "ForwardingProfileTimestamp"
    $warnAgeHours = 2

    Write-Log "Checking ForwardingProfileTimestamp registry value..." "INFO"
    $timestampValue = Get-ItemPropertyValue -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue

    if ([string]::IsNullOrEmpty($timestampValue)) {
        Write-Log "ForwardingProfileTimestamp is missing - the forwarding profile has never been downloaded. Ensure network connectivity to graph.microsoft.com and that the user is assigned to a forwarding profile in Entra portal." "WARNING"
        return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
    }

    try {
        $profileTime  = [datetime]::Parse($timestampValue, [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::RoundtripKind)
        $age          = (Get-Date).ToUniversalTime() - $profileTime.ToUniversalTime()
        $ageFormatted = "$([int]$age.TotalHours)h $($age.Minutes)m"

        if ($age.TotalHours -le $warnAgeHours) {
            Write-Log "ForwardingProfile was last retrieved $ageFormatted ago (UTC: $($profileTime.ToString('u'))) - profile is current." "SUCCESS"
            return $true
        } else {
            Write-Log "ForwardingProfile was last retrieved $ageFormatted ago (UTC: $($profileTime.ToString('u'))) - profile may be stale. To force a refresh: delete the ForwardingProfileTimestamp registry key and restart GlobalSecureAccessForwardingProfileService." "WARNING"
            return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
        }
    } catch {
        Write-Log "ForwardingProfileTimestamp value '$timestampValue' could not be parsed as a date: $_" "WARNING"
        return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
    }
}

#
# Function: Test-GSASecureDnsStatus
# Checks whether DoH is disabled in Chrome/Edge; active DoH prevents GSA from acquiring FQDN traffic.
#
function Test-GSASecureDnsStatus {
    $allPassed = $true
    $browsers  = @(
        @{ Name = 'Microsoft Edge'; Paths = @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKCU:\SOFTWARE\Policies\Microsoft\Edge') }
        @{ Name = 'Google Chrome';  Paths = @('HKLM:\SOFTWARE\Policies\Google\Chrome',  'HKCU:\SOFTWARE\Policies\Google\Chrome') }
    )

    Write-Log "Checking Secure DNS (DoH) policy settings - GSA requires DoH to be disabled..." "INFO"
    foreach ($browser in $browsers) {
        $dohFound = $false
        foreach ($path in $browser.Paths) {
            $dohMode = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue).DnsOverHttpsMode
            if ($dohMode -and $dohMode -ne "off") {
                Write-Log "$($browser.Name): Secure DNS is enabled (DnsOverHttpsMode = '$dohMode' at $path). GSA cannot acquire FQDN-based traffic when DoH is active. Set DnsOverHttpsMode to 'off' via Group Policy." "WARNING"
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

#
# Function: Test-GSAIPv6Status
# Checks whether IPv6 is enabled on active physical adapters; GSA does not support IPv6 traffic.
#
function Test-GSAIPv6Status {
    $warningsFound = $false
    Write-Log "Checking IPv6 binding on active physical network adapters - GSA does not support IPv6..." "INFO"
    try {
        $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
        if (-not $adapters) {
            Write-Log "No active physical network adapters found." "WARNING"
            return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
        }
        foreach ($adapter in $adapters) {
            $binding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
            if ($binding.Enabled) {
                Write-Log "IPv6 is ENABLED on adapter '$($adapter.Name)'. Disable it to prevent IPv6 traffic from bypassing the GSA tunnel." "WARNING"
                if ($LogLevel -eq "DEBUG") {
                    $v6addrs = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv6 -ErrorAction SilentlyContinue |
                               Where-Object { $_.IPAddress -ne '::1' }
                    foreach ($addr in $v6addrs) {
                        Write-Log "  IPv6 on '$($adapter.Name)': $($addr.IPAddress)/$($addr.PrefixLength)" "DEBUG"
                    }
                }
                $warningsFound = $true
            } else {
                Write-Log "IPv6 is disabled on adapter '$($adapter.Name)'." "INFO"
            }
        }
        if (-not $warningsFound) {
            Write-Log "IPv6 is disabled on all active physical adapters." "SUCCESS"
            return $true
        }
        return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
    } catch {
        Write-Log "Failed to check IPv6 adapter bindings: $_" "ERROR"
        return $false
    }
}

#
# Function: Test-GSAEventLog
# Reads the GSA Windows Event Log for Critical/Error events in the last hour.
#
function Test-GSAEventLog {
    $lookbackHours = 1
    $maxEvents     = 200

    # Discover the GSA event log name - Channel field from exported XML: 'Microsoft-Windows-Global Secure Access Client-Operational'
    $candidateNames = @(
        "Microsoft-Windows-Global Secure Access Client-Operational",
        "Microsoft-Windows-Global Secure Access Client-Kernel",
        "Microsoft-Global Secure Access Client/Operational",
        "Microsoft-Windows-GlobalSecureAccess-Client/Operational"
    )
    $logName = $candidateNames | Where-Object {
        Get-WinEvent -ListLog $_ -ErrorAction SilentlyContinue
    } | Select-Object -First 1

    if (-not $logName) {
        Write-Log "GSA event log not found on this system. The log channel has not been registered yet (this is normal on new installs or if no events have occurred)." "WARNING"
        return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
    }

    # Known event IDs with semantic category - from operational log enumeration
    $knownEvents = @{
        141 = @{ Category = 'Connection';      Description = 'Edge connection FAILED (GRPC could not be established)' }
        212 = @{ Category = 'Connection';      Description = 'Flow closed by server (private resource unreachable)' }
        230 = @{ Category = 'Connection';      Description = 'Private Access channel disabled' }
        631 = @{ Category = 'Connection';      Description = 'Disconnected from ALL channels' }
        632 = @{ Category = 'Connection';      Description = 'Partially connected - some channels are down' }
        638 = @{ Category = 'Connection';      Description = 'Device not connected to the network' }
        503 = @{ Category = 'Authentication';  Description = 'User authenticated successfully' }
    }

    Write-Log "Scanning GSA event log '$logName' for Critical/Error/Warning events in the last $lookbackHours hour(s)..." "INFO"
    try {
        $since  = (Get-Date).AddHours(-$lookbackHours)
        $all    = Get-WinEvent -LogName $logName -MaxEvents $maxEvents -ErrorAction Stop
        $errors = $all | Where-Object { $_.TimeCreated -ge $since -and $_.Level -le 3 }

        if (-not $errors -or $errors.Count -eq 0) {
            Write-Log "No Critical/Error/Warning events found in the GSA event log in the last $lookbackHours hour(s)." "SUCCESS"
            if ($LogLevel -eq "DEBUG") {
                $recentAll = $all | Where-Object { $_.TimeCreated -ge $since } | Select-Object -First 20
                if ($recentAll) {
                    Write-Log "  Recent events (all levels, last $lookbackHours hour):" "DEBUG"
                    foreach ($ev in $recentAll) {
                        $msg = ($ev.Message -replace '\s+', ' ').Trim()
                        if ($msg.Length -gt 150) { $msg = $msg.Substring(0, 147) + '...' }
                        $cat = if ($knownEvents.ContainsKey($ev.Id)) { $knownEvents[$ev.Id].Category } else { '' }
                        $catLabel = if ($cat) { "[$cat] " } else { '' }
                        Write-Log "  [$($ev.TimeCreated.ToString('HH:mm:ss'))] L$($ev.Level) EventId $($ev.Id) ${catLabel}: $msg" "DEBUG"
                    }
                }
            }
            return $true
        }

        Write-Log "Found $($errors.Count) Critical/Error/Warning event(s) in the GSA event log (last $lookbackHours hour):" "WARNING"
        foreach ($ev in ($errors | Select-Object -First 10)) {
            $known    = $knownEvents[$ev.Id]
            $catLabel = if ($known) { "[$($known.Category)] " } else { '' }
            $desc     = if ($known) { " ($($known.Description))" } else { '' }
            $msg      = ($ev.Message -replace '\s+', ' ').Trim()
            if ($msg.Length -gt 150) { $msg = $msg.Substring(0, 147) + '...' }
            Write-Log "  [$($ev.TimeCreated.ToString('HH:mm:ss'))] ${catLabel}EventId $($ev.Id)$desc" "WARNING"
            Write-Log "    $msg" "WARNING"
        }
        if ($errors.Count -gt 10) {
            Write-Log "  ... and $($errors.Count - 10) more event(s). Open Event Viewer for full details." "WARNING"
        }
        return [PSCustomObject]@{ Passed = $true; Warnings = $errors.Count }
    } catch {
        if ($_.Exception.Message -match "No events were found|not found") {
            Write-Log "No events in the GSA event log for the last $lookbackHours hour(s)." "SUCCESS"
            return $true
        }
        Write-Log "Could not read GSA event log '$logName': $_" "WARNING"
        return [PSCustomObject]@{ Passed = $true; Warnings = 1 }
    }
}

#
# Function: Test-GSAForwardingProfileRegistry
# Verifies the GSA ForwardingProfile registry key exists, is non-empty, and is parseable JSON.
# Based on testGSAClientProfile() from GSATool by mzmaili (https://github.com/mzmaili/GSATool)
#
function Test-GSAForwardingProfileRegistry {
    $allTestsPassed = $true
    $registryPath   = "HKLM:\SOFTWARE\Microsoft\Global Secure Access Client"
    $valueName      = "ForwardingProfile"

    # Check the registry key exists
    Write-Log "Checking ForwardingProfile registry key..." "INFO"
    $regProfile = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
    if (-Not $regProfile) {
        Write-Log "ForwardingProfile registry key does not exist. Ensure the forwarding profile is enabled and the user is assigned in Entra portal under Global Secure Access > Connect > Traffic forwarding." "ERROR"
        return $false
    }
    Write-Log "ForwardingProfile registry key exists." "SUCCESS"

    # Check the value is not empty
    Write-Log "Checking ForwardingProfile registry value is not empty..." "INFO"
    $profileValue = Get-ItemPropertyValue -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($profileValue)) {
        Write-Log "ForwardingProfile registry value is empty. Restart 'GlobalSecureAccessPolicyRetrieverService' (or 'GlobalSecureAccessForwardingProfileService') to re-retrieve the profile configuration." "ERROR"
        return $false
    }
    Write-Log "ForwardingProfile registry value is populated." "SUCCESS"

    # Validate the JSON is parseable
    Write-Log "Validating ForwardingProfile JSON..." "INFO"
    try {
        $json = $profileValue | ConvertFrom-Json
    } catch {
        Write-Log "ForwardingProfile JSON is corrupt or unparseable: $_. Restart 'GlobalSecureAccessPolicyRetrieverService' to refresh the profile." "ERROR"
        return $false
    }

    # Report which channels are configured
    $channels = $json.policy.channels
    if (-Not $channels -or $channels.Count -eq 0) {
        Write-Log "ForwardingProfile JSON contains no channels. Ensure at least one traffic forwarding profile (M365 / Private / Internet) is enabled in Entra portal." "WARNING"
        $allTestsPassed = $false
    } else {
        Write-Log "ForwardingProfile JSON is valid. Configured channel(s): $($channels.name -join ', ')." "SUCCESS"
        if ($LogLevel -eq "DEBUG") {
            if ($json.tenantId) { Write-Log "  TenantId: $($json.tenantId)" "DEBUG" }
            foreach ($ch in $channels) {
                $edges = @($ch.edgesSettings.primaryEdges) + @($ch.edgesSettings.secondaryEdges)
                Write-Log "  Channel '$($ch.name)': $($edges.Count) edge(s), DiagnosticUri: $($ch.diagnosticUri)" "DEBUG"
                foreach ($e in $edges) { Write-Log "    Edge: $($e.edgeAddress)" "DEBUG" }
            }
        }
    }

    return $allTestsPassed
}

#
# Function: Test-GSASyntheticRoutes
# Checks whether GSA synthetic IP routes (6.6.x.x) are present in the routing table.
# Inspired by GSATool's synthetic IP tunnel verification by mzmaili (https://github.com/mzmaili/GSATool)
#
function Test-GSASyntheticRoutes {
    Write-Log "Checking for GSA synthetic IP routes (6.6.x.x) in the routing table..." "INFO"

    try {
        $gsaRoutes = Get-NetRoute -ErrorAction Stop | Where-Object { $_.DestinationPrefix -like "6.6.*" }
    } catch {
        Write-Log "Failed to query routing table: $_" "ERROR"
        return $false
    }

    if ($gsaRoutes -and $gsaRoutes.Count -gt 0) {
        Write-Log "Found $($gsaRoutes.Count) GSA synthetic route(s) - tunnel is active and routing traffic." "SUCCESS"
        foreach ($route in $gsaRoutes) {
            Write-Log "  $($route.DestinationPrefix) via $($route.NextHop) (interface: $($route.InterfaceAlias))" "DEBUG"
        }
        return $true
    } else {
        Write-Log "No GSA synthetic IP routes (6.6.x.x) found. The tunnel may not be active yet - this is expected if no Private/M365/Internet traffic has flowed since the client started." "WARNING"
        return [PSCustomObject]@{
            Passed   = $true
            Warnings = 1
        }
    }
}

#
# Function: Test-GSAPrivateDnsResolver
# Queries the GSA-internal DNS resolver at 6.6.255.254 to confirm Private Access tunnel is active.
# Inspired by Resolve-DnsName -Server 6.6.255.254 in GSATool by mzmaili (https://github.com/mzmaili/GSATool)
#
function Test-GSAPrivateDnsResolver {
    Write-Log "Querying GSA Private DNS resolver (6.6.255.254) via TCP..." "INFO"

    try {
        # Any response (including NXDOMAIN) confirms the resolver is reachable through the tunnel
        $result = Resolve-DnsName -Name "connectivity.check.gsa.internal" -Server 6.6.255.254 -TcpOnly -ErrorAction Stop
        Write-Log "GSA Private DNS resolver (6.6.255.254) responded - Private Access tunnel is active." "SUCCESS"
        return $true
    } catch {
        $errorMsg = $_.Exception.Message
        # DNS error codes like NXDOMAIN / SERVFAIL still mean the server responded
        if ($errorMsg -match "DNS name does not exist|NXDOMAIN|server failure|SERVFAIL|query refused") {
            Write-Log "GSA Private DNS resolver (6.6.255.254) responded (DNS error expected for test name) - tunnel is active." "SUCCESS"
            return $true
        } else {
            Write-Log "GSA Private DNS resolver (6.6.255.254) is unreachable: $errorMsg. Ensure Private Access is enabled and the GSA tunnel services are running." "ERROR"
            return $false
        }
    }
}

#
# Function: Test-GSAServiceStatus
# Checks that all required Global Secure Access Windows services are running.
# Based on checks from GSATool by mzmaili (https://github.com/mzmaili/GSATool)
#
function Test-GSAServiceStatus {
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
            if ($LogLevel -eq "DEBUG") {
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
        if ($LogLevel -eq "DEBUG") {
            $running = if ($fpSvc.Status -eq 'Running') { $fpSvc } else { $fpSvc2 }
            Write-Log "  Name: $($running.Name), StartType: $($running.StartType)" "DEBUG"
        }
    } else {
        Write-Log "Forwarding Profile Service is not running. Ensure GlobalSecureAccessForwardingProfileService (or GlobalSecureAccessPolicyRetrieverService) is started." "ERROR"
        $allTestsPassed = $false
    }

    return $allTestsPassed
}

#
# Function: Test-DeviceEntraStatus
# Checks that the device is Entra Joined and that Private Access is not user-disabled.
# Based on checks from GSATool by mzmaili (https://github.com/mzmaili/GSATool)
#
function Test-DeviceEntraStatus {
    $allTestsPassed = $true

    # Check Entra ID join status via dsregcmd
    Write-Log "Checking if device is connected to Microsoft Entra ID..." "INFO"
    try {
        $dsregOutput = dsregcmd /status 2>&1
        $entraJoined = ($dsregOutput | Select-String -Pattern 'AzureADJoined' -SimpleMatch) -match 'YES'

        if ($entraJoined) {
            Write-Log "Device '$($env:COMPUTERNAME)' is connected to Microsoft Entra ID." "SUCCESS"
            if ($LogLevel -eq "DEBUG") {
                foreach ($field in @('DomainJoined', 'TenantId', 'TenantDisplayName', 'AzureAdPrtUpdateTime')) {
                    $line = $dsregOutput | Select-String -Pattern "^\s*$field\s*:" | Select-Object -First 1
                    if ($line) { Write-Log "  $field : $(($line.ToString() -split ':', 2)[1].Trim())" "DEBUG" }
                }
            }
        } else {
            Write-Log "Device '$($env:COMPUTERNAME)' is NOT connected to Microsoft Entra ID. Ensure the device is Entra Joined or Hybrid Entra Joined." "ERROR"
            $allTestsPassed = $false
        }
    } catch {
        Write-Log "Failed to determine Entra ID join status via dsregcmd: $_" "ERROR"
        $allTestsPassed = $false
    }

    # Check if user has locally disabled Private Access
    Write-Log "Checking Private Access user-disable registry flag..." "INFO"
    $reg = Get-ItemProperty -Path 'Registry::HKCU\Software\Microsoft\Global Secure Access Client' -ErrorAction SilentlyContinue
    if ($reg.IsPrivateAccessDisabledByUser -eq 1) {
        Write-Log "Private Access is disabled by user setting (IsPrivateAccessDisabledByUser = 1). Set the value to 0 in HKCU\Software\Microsoft\Global Secure Access Client to re-enable." "WARNING"
    } else {
        Write-Log "Private Access is enabled (IsPrivateAccessDisabledByUser is not set or is 0)." "SUCCESS"
    }

    return $allTestsPassed
}

#
# Function: Test-grpcProxy 
# checks if the grpc_proxy environment variable is set
# 
function Test-grpcProxy 
{
    try 
    {
        # Read the grpc_proxy environment variable from the machine (system) context
        $machineGrpcProxy = [System.Environment]::GetEnvironmentVariable("grpc_proxy", "Machine")
        # Read the grpc_proxy environment variable from the user context
        $userGrpcProxy = [System.Environment]::GetEnvironmentVariable("grpc_proxy", "User")

        if ($machineGrpcProxy) 
        {
            Write-Log -Message "Machine-level grpc_proxy variable is set to: $machineGrpcProxy" -Level "WARNING"
        } else {
            Write-Log -Message "Machine-level grpc_proxy variable is not set." -Level "INFO"
        }

        if ($userGrpcProxy) 
        {
            Write-Log -Message "User-level grpc_proxy variable is set to: $userGrpcProxy" -Level "WARNING"
        } else 
        {
            Write-Log -Message "User-level grpc_proxy variable is not set." -Level "INFO"
        }

        # Return true if both variables are set; otherwise, false
        if ($machineGrpcProxy -and $userGrpcProxy) 
        {
            return $true
        } else {
            return $false
        }
    }
    catch 
    {
        Write-Log -Message "Error checking grpc_proxy environment variables: $_" -Level "ERROR"
        return $false
    }
}

#
# Function: Test-SystemWebProxy
# checks system webproxy configuration using GetProxy
#
function Test-SystemWebProxy {
    param (
        [string]$TargetUrl = 'http://www.microsoft.com'
    )

    try {
        # Create a Uri object from the target URL
        $uri = New-Object System.Uri($TargetUrl)

        # Get the system's default proxy instance
        $webProxy = [System.Net.WebRequest]::GetSystemWebProxy()

        # Get the proxy URI for the target URL
        $proxyUri = $webProxy.GetProxy($uri)

        # Determine if a proxy is being used
        if ($proxyUri -ne $uri) 
        {
            Write-Log -Message "Proxy detected for $TargetUrl : $proxyUri" -Level "WARNING"
            return $proxyUri
        } 
        else 
        {            
            return $null
        }
    } catch 
    {
        Write-Log -Message "Error during proxy detection: $_" -Level "ERROR"
        return $null
    }
}

#
# Function: Test-ProxyDetection # 
# This function tests for the presence of an outbound proxy by:
# 1. Checking the system proxy configuration
# 2. Testing for transparent proxy detection via HTTP headers
# 3. Testing for authenticating proxy detection via HTTP 407 response
#
function Test-ProxyDetection {
    param (
        # URLs to test; you can adjust these as needed.
        [string]$TestUrlHttp = "http://www.msftconnecttest.com/connecttest.txt",
        [string]$TestUrlHttps = "https://www.microsoft.com",
        [int]$TimeoutSec = 10
    )

    # Initialize result object.
    $result = [PSCustomObject]@{
        ProxyFound                 = $false
        SystemProxyConfigured      = $false
        ProxyAddress               = $null
        TransparentProxyDetected   = $false
        AuthenticatingProxyDetected= $false
        Passed                     = $true
        Warnings                   = 0
    }

    #
    # Check System Proxy Configuration
    #
    try {
        $netshOutput = netsh winhttp show proxy 2>&1
        if ($netshOutput -match "Direct access") {
            $result.SystemProxyConfigured = $false
            Write-Log -Message "System proxy is not configured (Direct access mode)." -Level "INFO"
        } else {
            $result.SystemProxyConfigured = $true
            Write-Log -Message "System proxy is configured." -Level "INFO"
            if ($netshOutput -match "Proxy Server\s*:\s*(.+)") {
                $result.ProxyAddress = $matches[1].Trim()
                Write-Log -Message "Detected system proxy address: $($result.ProxyAddress)" -Level "WARNING"
                $result.ProxyFound = $true
                $result.Warnings++
            }
        }
    } catch {
        Write-Log -Message "Error retrieving system proxy settings: $_" -Level "ERROR"
        $result.Passed = $false
    }

    #
    # Check for grpc proxy settings
    #
    if (Test-grpcProxy) {
        Write-Log -Message "grpc_proxy variables are set." -Level "WARNING"
        $result.Warnings++
    } else {
        Write-Log -Message "NO grpc_proxy environment variables are set." -Level "INFO"
    }

    #
    # Additional test for WebRequest proxy
    #
    $proxy = Test-SystemWebProxy -TargetUrl 'http://www.microsoft.com'
    if ($proxy) {
        Write-Log -Message "SystemWebProxy: Found proxy: $proxy" -Level "WARNING"
        $result.ProxyFound = $true
        $result.Warnings++
    } else {
        Write-Log -Message "SystemWebProxy: Direct connection will be used." -Level "INFO"
    }

    #
    # Transparent Proxy Detection (HTTP)
    #
    try {
        $responseHttp = Invoke-WebRequest -Uri $TestUrlHttp -UseBasicParsing -TimeoutSec $TimeoutSec
        Write-Log -Message "HTTP test request to $TestUrlHttp succeeded." -Level "INFO"

        if ($responseHttp.Headers["Via"] -or $responseHttp.Headers["X-Forwarded-For"]) {
            $result.TransparentProxyDetected = $true
            Write-Log -Message "Transparent proxy detected via HTTP header(s): $responseHttp.Headers" -Level "WARNING"
            $result.ProxyFound = $true
            $result.Warnings++
        }
    } catch {
        Write-Log -Message "HTTP test error: $_" -Level "ERROR"
        $result.Passed = $false
    }

    #
    # Authenticating Proxy Detection (HTTPS)
    #
    try {
        Invoke-WebRequest -Uri $TestUrlHttps -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop | Out-Null
        Write-Log -Message "HTTPS test request to $TestUrlHttps succeeded." -Level "INFO"
    } catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 407) {
            $result.AuthenticatingProxyDetected = $true
            Write-Log -Message "Authenticating proxy detected (HTTP 407 response)." -Level "WARNING"
            $result.ProxyFound = $true
            $result.Warnings++
        } else {
            Write-Log -Message "HTTPS test error: $_" -Level "ERROR"
            $result.Passed = $false
        }
    }

    return $result
}

# 
# Test-EntraIDConnectivity - test the main entra ID endpoints
# 
function Test-EntraIDConnectivity {
    param (
        [string[]]$Endpoints = @(
            "https://login.microsoftonline.com",         # Microsoft Azure Worldwide
            "https://login.windows.net",                 # Token provider for Entra ID/Azure AD
            "https://login.microsoft.com",               # 
            "https://logincert.microsoftonline.com",     #
            "https://graph.microsoft.com",               # Microsoft Graph API
            "https://sts.windows.net",                   # Security Token Service
            "https://login.live.com",                    # Microsoft Account endpoint 
            "https://aadcdn.msauth.net",                 # CDN for loging prompt rendering              
            "https://aadcdn.msftauthimages.net",         # CDN for loging prompt rendering
            "https://enterpriseregistration.windows.net",# Device Registration endpoint
            "https://device.login.microsoftonline.com",  # Device Auth
            "https://certauth.login.microsoftonline.com" # CBA AuthN
        ),
        [int]$Timeout = 15
    )

    $allTestsPassed = $true

    foreach ($url in $Endpoints) {
        try {
            Write-Log -Message "Testing connectivity to $url ..." -Level "INFO"

            # Create a TCP connection to extract certificate details
            $uri = [System.Uri]::new($url)
            $tcpClient = [System.Net.Sockets.TcpClient]::new($uri.Host, 443)
            $sslStream = [System.Net.Security.SslStream]::new($tcpClient.GetStream(), $false, { $true })
            try {
                $sslStream.AuthenticateAsClient($uri.Host)

                # Log certificate details if in DEBUG mode
                if ($LogLevel -eq "DEBUG") {
                    $remoteCertificate = $sslStream.RemoteCertificate
                    if ($remoteCertificate) {
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $remoteCertificate
                        Write-Log "TLS Certificate Details for $url :" "DEBUG"
                        Write-Log "  Subject: $($cert.Subject)" "DEBUG"
                        Write-Log "  Issuer: $($cert.Issuer)" "DEBUG"
                        Write-Log "  Valid From: $($cert.NotBefore)" "DEBUG"
                        Write-Log "  Valid Until: $($cert.NotAfter)" "DEBUG"
                        Write-Log "  Thumbprint: $($cert.Thumbprint)" "DEBUG"
                    } else {
                        Write-Log "No TLS certificate information available for $url." "DEBUG"
                    }
                }
            } finally {
                $sslStream.Dispose()
                $tcpClient.Close()
            }

            # Perform the HTTP request
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $Timeout
            if ($response.StatusCode -eq 200) {
                Write-Log -Message "Successfully connected to $url" -Level "SUCCESS"
            }
        } 
        catch [System.Net.WebException] {
            if ($_.Exception.Response -and ($_.Exception.Response.StatusCode -ge 400 -and $_.Exception.Response.StatusCode -lt 500)) {
                Write-Log -Message "Successfully connected to '$url'. Received HTTP status code: $($_.Exception.Response.StatusCode) ($($_.Exception.Response.StatusDescription)). This is expected for some endpoints." -Level "WARNING"
            } else {
                Write-Log -Message "Failed to connect to $url - $($_.Exception.Message)" -Level "ERROR"
                $allTestsPassed = $false
            }
        }
        catch {
            Write-Log -Message "An unexpected error occurred while connecting to $url - $($_.Exception.Message)" -Level "ERROR"
            $allTestsPassed = $false
        }
    }
    return $allTestsPassed
}

#
# Function: Test-EntraIDUserAuthN
# performs Test authentication to Entra ID using MSAL
#
function Test-EntraIDUserAuthN
{
    $token = Get-MSALToken -ClientId "d3590ed6-52b3-4102-aeff-aad2292ab01c" -Scopes "https://graph.microsoft.com/.default"

    try 
    {
        Write-Log -Message "Attempting authentication to Entra ID" -Level "INFO"
        $token = Get-MSALToken -ClientId "d3590ed6-52b3-4102-aeff-aad2292ab01c" -Scopes "https://graph.microsoft.com/.default"

        if ($token.AccessToken) 
        {
            Write-Log -Message "Authentication successful. Token retrieved." -Level "INFO"        
        } else {
            Write-Log -Message "Authentication failed. No token received." -Level "ERROR"        
        }
    } 
    catch {
        Write-Log -Message "Authentication failed: $($_.Exception.Message)" -Level "ERROR"    
    }
}

#
# function Test-DiagnosticUri performs a test on the DiagnosticUri
# It will check if the URI is reachable and log the RTT
#
function Test-DiagnosticUris {
    param (
        [string[]]$DiagnosticUris
    )

    if (-not $DiagnosticUris -or $DiagnosticUris.Count -eq 0) {
        Write-Log "No DiagnosticUris to test." "WARNING"
        return $false
    }

    $allPassed = $true

    # Iterate through each URI and perform the test
    foreach ($uri in $DiagnosticUris) {
        try 
        {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 10
            $stopwatch.Stop()

            $rtt = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                if ($rtt -gt 200) {
                    Write-Log "DiagnosticUrl test $uri succeeded. RTT: $rtt ms (High RTT)" "WARNING"
                } else {
                    Write-Log "DiagnosticUrl test $uri succeeded. RTT: $rtt ms" "SUCCESS"
                }
            } 
            else 
            {
                # we got a non 200 code back, Log the status code and RTT
                Write-Log "DiagnosticUrl test $uri returned status code $($response.StatusCode). RTT: $rtt ms" "WARNING"
                $allPassed = $false
            }
        } 
        catch 
        {
            Write-Log "DiagnosticUrl $uri failed: $($_.Exception.Message)" "ERROR"
            $allPassed = $false
        }
    }

    return $allPassed
}

# 
# Function: Get-GSAEndpoints
# This function loads the JSON content from the registry, extracts channels, edge addresses, and diagnostic URIs.
#
function Get-GSAEndpoints {
    param (
        [string]$RegistryValueName = "ForwardingProfile"
    )

    # Load the JSON content from the registry
    $jsonContent = Get-JsonFromRegistry -ValueName $RegistryValueName
    [string[]]$DiagnosticUris = @()
    [string[]]$gsaMainEndpointAddrs = @()

    # Check if we can load the configuration
    if (-Not $jsonContent) { Write-Log "Failed to load GSA client configuration, Terminating script." "ERROR"; return $null }

    # Check if we have a valid JSON and can get the channels
    $gsaChannels = Get-GSAMainEndpoints -jsonContent $jsonContent
    if ($gsaChannels.Count -eq 0) { Write-Log "No channels/edge addresses found. Exiting." "ERROR"; return $null }

    # Build the list of endpoints
    foreach ($entry in $gsaChannels) {
        Write-Log "Found channel: $($entry.ChannelName)" "DEBUG"
        foreach ($edge in $entry.EdgeAddresses) {
            $gsaMainEndpointAddrs += $entry.EdgeAddresses
            Write-Log " -> Edge: $($edge)" "DEBUG"
        }
        Write-Log "Diagnostic URI: $($entry.DiagnosticUri)" "DEBUG"
        $DiagnosticUris += $entry.DiagnosticUri  # Append to the string array
    }

    # Add APS
    $gsaMainEndpointAddrs += "aps.globalsecureaccess.microsoft.com"

    # Check if we have endpoints to test against
    if ($gsaMainEndpointAddrs.Count -eq 0) { Write-Log "No edge addresses found. Exiting." "ERROR"; return $null }
    if ($DiagnosticUris.Count -eq 0) { Write-Log "No DiagnosticUris found. Exiting." "ERROR"; return $null }

    return [PSCustomObject]@{
        MainEndpoints = $gsaMainEndpointAddrs
        DiagnosticUris = $DiagnosticUris
    }
}

# 
# Main Script Execution
# 
# Here we call the functions to perform the tests and log the results.
# We will use the GSA client configuration from the registry to get the endpoints to test against.
#

# Initialize counters for passed, failed, and warning tests
$testsPassed = 0
$testsFailed = 0
$testsWithWarnings = 0

# Initialize the hashtable to store test results
$testResults = @{}

Write-Log "========= GSA Client Connectivity Checker v. $ScriptVer Started ========="

# Try to load the GSA client configuration from the registry
$gsaEndpoints = Get-GSAEndpoints -RegistryValueName "ForwardingProfile"

# Check if we have endpoints to test against else exit
if (-Not $gsaEndpoints) { exit }

$gsaMainEndpointAddrs = $gsaEndpoints.MainEndpoints
$DiagnosticUris = $gsaEndpoints.DiagnosticUris

# Define a hashtable of tests (explicitly ordered)
$tests = [ordered]@{
    "GSA Service Status"               = { Test-GSAServiceStatus }
    "Device Entra Status"              = { Test-DeviceEntraStatus }
    "GSA Primary Refresh Token"        = { Test-GSAPrimaryRefreshToken }
    "GSA Forwarding Profile Registry"  = { Test-GSAForwardingProfileRegistry }
    "GSA Forwarding Profile Timestamp" = { Test-GSAForwardingProfileTimestamp }
    "Basic Internet connectivity"      = { Test-InternetConnectivity }
    "Proxy Detection"                  = { Test-ProxyDetection }
    "GSA Secure DNS Status"           = { Test-GSASecureDnsStatus }
    "GSA IPv6 Status"                 = { Test-GSAIPv6Status }
    "DNS Resolution"                   = { param($param1) Test-DnsResolution -fqdnList $param1 }
    "Entra ID Connectivity"            = { Test-EntraIDConnectivity }
    "TLS Connectivity"                = { param($param1) Test-TLSConnection -fqdnList $param1 }
    "mTLS Connectivity"               = { param($param1) Test-mTLSConnection -fqdnList $param1 }
    "Diagnostics Connectivity"        = { param($param1) Test-DiagnosticUris -DiagnosticUris $param1 }
    "GSA Synthetic Routes"            = { Test-GSASyntheticRoutes }
    "GSA Private DNS Resolver"        = { Test-GSAPrivateDnsResolver }
    "GSA Event Log"                   = { Test-GSAEventLog }
}

# Table to hold the parameters for each test that needs parameters
$testParams = [ordered]@{
    "DNS Resolution"   = @{ param1 = $gsaMainEndpointAddrs }
    "TLS Connectivity" = @{ param1 = $gsaMainEndpointAddrs }
    "mTLS Connectivity" = @{ param1 = $gsaMainEndpointAddrs }
    "Diagnostics Connectivity" = @{ param1 = $DiagnosticUris }
}

# Run all tests in the defined order
foreach ($testName in $tests.Keys) {
    Write-Log -Message "===== Executing: $testName =========" -Level "INFO"
    $scriptBlock = $tests[$testName]
    $params = $testParams[$testName]

    if ($params) {
        $result = & $scriptBlock @params
    } else {
        $result = & $scriptBlock
    }
    # If a test function leaked extra pipeline output, extract the PSCustomObject
    if ($result -is [array]) {
        $result = $result | Where-Object { $_ -is [PSCustomObject] } | Select-Object -Last 1
    }

    # Store the result in the hashtable
    $testResults[$testName] = $result

    # Check if the result is a PSCustomObject with warnings
    if ($result -is [PSCustomObject]) {
        if ($result.Warnings -gt 0) {
            Write-Log "===== $testName : WARNINGS =========" "WARNING"
            $testsWithWarnings++
        }
        if ($result.Passed -eq $true) {
            Write-Log "===== $testName : PASSED =========" "SUCCESS"
            $testsPassed++
        } elseif ($result.Passed -eq $false) {
            Write-Log "===== $testName : FAILED =========" "ERROR"
            $testsFailed++
        }
    } else {
        # Handle non-object results (true/false)
        if ($result -eq $true) {
            Write-Log "===== $testName : PASSED =========" "SUCCESS"
            $testsPassed++
        } elseif ($result -eq $false) {
            Write-Log "===== $testName : FAILED =========" "ERROR"
            $testsFailed++
        }
    }
}

# Log final summary
Write-Log "========= GSA Client Connectivity Check Completed =========" "INFO"

# Create a detailed summary table
$summaryTable = @()
foreach ($testName in $testResults.Keys) {
    $result = if ($testResults[$testName] -is [PSCustomObject]) {
        if ($testResults[$testName].Passed -eq $true) { "PASSED" } else { "FAILED" }
    } else {
        if ($testResults[$testName] -eq $true) { "PASSED" } else { "FAILED" }
    }
    $warnings = if ($testResults[$testName] -is [PSCustomObject] -and $testResults[$testName].Warnings) {
        $testResults[$testName].Warnings
    } else {
        0
    }
    $summaryTable += [PSCustomObject]@{
        TestName = $testName
        Result   = $result
        Warnings = $warnings
    }
}

# Display the summary table without extra blank lines
Write-Log "Test Results Summary:" "INFO"
$summaryTable | Format-Table -AutoSize | Out-String -Stream | ForEach-Object { Write-Log $_ "INFO" }

# Log overall results
Write-Log "Summary: $testsPassed tests passed, $testsFailed tests failed, $testsWithWarnings tests with warnings." "INFO"

if ($testsFailed -eq 0 -and $testsWithWarnings -eq 0) {
    Write-Log "All tests passed successfully!" "SUCCESS"
} elseif ($testsFailed -eq 0) {
    Write-Log "All tests passed, but some tests generated warnings. Please review the logs for details." "WARNING"
} else {
    Write-Log "Some tests failed. Please review the logs for details." "ERROR"
}
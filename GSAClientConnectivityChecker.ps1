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

.EXAMPLE
    .\GSA-Diagnostics.ps1 -LogLevel DEBUG

.EXAMPLE
    .\GSA-Diagnostics.ps1 -LogLevel ERROR

.NOTES
    Author: GSA CxE Team (Microsoft - tdetzner)
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

# Ensure directory exists
if (-Not (Test-Path $BasePath)) {
    New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
}

# global lock Object used for logging thread safety
if (-not $Global:LogLockObject) {
    $Global:LogLockObject = New-Object System.Object
}

# 
# Function: Logging with Console Output (thread safe)
# 
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
   try 
   {
       $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
       $logMessage = "[$timestamp] [$level] $message"

       if ($messageIndex -le $currentIndex -or $Level -eq "SUCCESS") 
       {
                $color = switch ($Level){
                    "ERROR"   { "Red" }
                    "WARNING" { "Yellow" }
                    "INFO"    { "Gray" }
                    "DEBUG"   { "Cyan" }
                "SUCCESS" { "Green" }
                }
                Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
        }

       # Use a file stream to write to the log file to avoid file access conflicts
       $fileStream = [System.IO.File]::Open($LogFilePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
       $streamWriter = New-Object System.IO.StreamWriter($fileStream)
       try 
       {
           $streamWriter.WriteLine($logMessage)
       } 
       finally
       {
           $streamWriter.Close()
           $fileStream.Close()
       }
   }   
   finally 
   {
       [System.Threading.Monitor]::Exit($Global:LogLockObject)
   }
}

# ---------------------------------------------
# Function: Test-IsElevated checks for admin rights
# ---------------------------------------------
function Test-IsElevated 
{
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
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
        $jsonString = Get-ItemPropertyValue -Path $Global:GSAFwdProfileRegistryPath -Name $ValueName -ErrorAction Stop
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

    foreach ($channel in $jsonContent.policy.channels) 
    {
        $edges = @()
        $channelName = $channel.name
        $diagnosticUri = $channel.diagnosticUri

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
        $fqdnList | Out-File -Encoding utf8 $filePath -Force
        Write-Log "Edge addresses saved to: $filePath" "SUCCESS"
    } catch {
        Write-Log "Failed to save edge addresses: $_" "ERROR"
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

    try 
    {
        $udpClient = [System.Net.Sockets.UdpClient]::new()
        $udpClient.Connect($IPAddress, $Port)
        Write-Log -Message "Testing UDP connectivity to $IPAddress on port $Port" -Level "INFO"

        # Construct a simple DNS query for nxdomain.com to minimize data transmission
        $query = [byte[]](0xAA, 0xAA, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x6e, 0x78, 0x64, 0x6f, 0x6d, 0x61,0x69,0x6e,0x03,0x63,0x6f,0x6d,0x00,0x00,0x01,0x00,0x00)

        $udpClient.Send($query, $query.Length)

        # blocking receive until we get a response or timeout
        # $response = $udpClient.Receive([ref]$IPAddress, [ref]$Port)
        # $udpClient.Close()
        
        $receiveTask = $udpClient.ReceiveAsync()
        if ($receiveTask.Wait($Timeout)) {
            $response = $receiveTask.Result
            $udpClient.Close()
            return $true
        } 
        
        else 
        {
            $udpClient.Close()
            return $false
        }        
    } 
    catch 
    {
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

    $allTestsPassed = $true

    # Check for active network interfaces with default routes
    $defaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne "::" }
    if ($defaultRoutes) {
        Write-Log "Active network interfaces with default routes detected." "INFO"
    } else {
        Write-Log "No active network interfaces with default routes found." "ERROR"
        $allTestsPassed = $false
    }

    # Test reachability of specified websites
    foreach ($site in $Websites) {
        $testResult = Test-NetConnection -ComputerName $site -InformationLevel Quiet
        if ($testResult) {
            Write-Log "Website $site is reachable." "INFO"
        } 
        else 
        {
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
        else 
        {
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
        # Append the CNAME target.
        $chain += $record.Name
        # Recursively check for additional CNAMEs.
        $childChain = Get-DnsChain -fqdn $record.Name -depth ($depth + 1) -visited $visited
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

    foreach ($fqdn in $fqdnList) 
    {
        Write-Log "Checking DNS resolution for: $fqdn" "INFO"

        try 
        {
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
                Write-Log "CNAME chain for $fqdn : $fqdn -> $($cnameChain -join ' -> ')" "INFO"
            } else {
                Write-Log "No CNAME records found for $fqdn." "INFO"
            }
        } 
        catch 
        { 
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
        Write-Log "Checking connection to: $fqdn on port $port "

        $tcpClient = New-Object System.Net.Sockets.TcpClient
        try {
            $tcpClient.Connect($fqdn, $port)
            Write-Log "TCP connection successful to $fqdn" "SUCCESS"
        } 
        catch 
        {
            Write-Log "TCP connection failed to $fqdn : $_" "ERROR"
            $allTestsPassed = $false
            continue
        }

        $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, ({ $true }))
        try {
            $sslStream.AuthenticateAsClient($fqdn)
            Write-Log "TLS handshake successful with $fqdn" "SUCCESS"
        } 
        catch {
            Write-Log "TLS handshake failed with $fqdn : $_" "ERROR"
            $allTestsPassed = $false
        } 
        finally {
            $sslStream.Dispose()
            $tcpClient.Close()
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
    $runningElevated = Test-IsElevated

    if (-not ($runningElevated)) 
    {
        Write-Log "This script is not running elevated" "WARNING"
        Write-Log "mTLS checks will most likely fail, due to missing permissions on the computers mTLS certificate private key(s)" "WARNING"    
    }    

    # Retrieve mTLS-capable certificates from the LocalMachine "My" store.
    $mtlsCertificates = Get-mTLSCertificates

    if ($mtlsCertificates.Count -eq 0) 
    {
        Write-Log "No mTLS-capable certificates were found." "WARNING"
        Write-Log "This could be normal, if the tenant is not yet onboarded to mTLS" "WARNING"
        $allTestsPassed = $false
        return $allTestsPassed
    } 
    else 
    {
        Write-Log "Found $($mtlsCertificates.Count) mTLS-capable GSA client certificate(s)." "SUCCESS"
    }

    foreach ($fqdn in $fqdnList) 
    {
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
                if ($ClientCert) {
                    $clientCerts.Add($ClientCert)
                }            
                # Attempt the mTLS handshake using TLS 1.2
                $sslStream.AuthenticateAsClient($fqdn, $clientCerts, [System.Security.Authentication.SslProtocols]::Tls12, $false) 
                $ismTLSdone = $sslStream.Ismutuallyauthenticated
                Write-Log "mTLS handshake succeeded for $fqdn with certificate $($ClientCert.Subject) mTLS: $ismTLSdone" "SUCCESS"
            }
            catch 
            {
                if (-not ($runningElevated)) 
                {
                    # the script is not running elevated, we will skip the error
                    Write-Log "mTLS handshake failed for $fqdn " "WARNING"   
                    Write-Log "Expected due to not running elevated. Run again with elevation" "WARNING"
                }
                else { Write-Log "mTLS handshake failed for $fqdn with certificate $($ClientCert.Subject) : $_" "ERROR" }
                $allTestsPassed = $false
            }
            finally 
            {
                $sslStream.Dispose()
                $tcpClient.Close()
            }
        }
    }
    return $allTestsPassed
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
        ProxyFound  		       = $false  
        SystemProxyConfigured      = $false
        ProxyAddress               = $null
        TransparentProxyDetected   = $false
        AuthenticatingProxyDetected= $false
    }

    #
    # Check System Proxy Configuration
    #
    try 
    {
        # BUGBUG: the below code only works on ENU OS versions
        $netshOutput = netsh winhttp show proxy 2>&1
        if ($netshOutput -match "Direct access") {
            $result.SystemProxyConfigured = $false
            Write-Log -Message "System proxy is not configured (Direct access mode)." -Level "Info"
        }
        else {
            $result.SystemProxyConfigured = $true
            Write-Log -Message "System proxy is configured." -Level "Info"
            if ($netshOutput -match "Proxy Server\s*:\s*(.+)") {
                $result.ProxyAddress = $matches[1].Trim()
                Write-Log -Message "Detected system proxy address: $($result.ProxyAddress)" -Level "WARNING"
                $result.ProxyFound = $true
            }
        }
    } 
    catch {
        Write-Log -Message "Error retrieving system proxy settings: $_" -Level "Error"
    }

    # 
    # Check for gprc proxy settings
    # 
    if (Test-grpcProxy) 
    {
        Write-Log -Message "grpc_proxy variables is set." -Level "WARNING"
    } else 
    {
        Write-Log -Message "NO grpc_proxy environment variables are set." -Level "INFO"
    }

    #
    # additional test for WebRequest proxy
    # 
    $proxy = Test-SystemWebProxy -TargetUrl 'http://www.microsoft.com'
    if ($proxy) 
    {
        Write-Log -Message "SystemWebProxy: Found proxy: $proxy" -Level "WARNING"
        $result.ProxyFound = $true
    } 
    else 
    {
        Write-Log -Message "SystemWebProxy: Direct connection will be used." -Level "INFO"
    }

    # 
    # Transparent Proxy Detection (HTTP)
    # 
    try {
        $responseHttp = Invoke-WebRequest -Uri $TestUrlHttp -UseBasicParsing -TimeoutSec $TimeoutSec
        Write-Log -Message "HTTP test request to $TestUrlHttp succeeded." -Level Info

        # Check for common proxy headers.
        if ($responseHttp.Headers["Via"] -or $responseHttp.Headers["X-Forwarded-For"]) {
            $result.TransparentProxyDetected = $true
            Write-Log -Message "Transparent proxy detected via HTTP header(s): $responseHttp.Headers" -Level Warning
            $result.ProxyFound = $true
        }
    } 
    catch {
        Write-Log -Message "HTTP test error: $_" -Level Error
    }

    # 
    # Authenticating Proxy Detection (HTTPS)
    # 
    try 
    {
        # Try an HTTPS request without credentials. 
        # If an authenticating proxy is in the path, you may receive a 407.
        $responseHttps = Invoke-WebRequest -Uri $TestUrlHttps -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        Write-Log -Message "HTTPS test request to $TestUrlHttps succeeded." -Level Info
    } 
    catch 
    {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 407) {
            $result.AuthenticatingProxyDetected = $true
            Write-Log -Message "Authenticating proxy detected (HTTP 407 response)." -Level Warning
            $result.ProxyFound = $true
        } else {
            Write-Log -Message "HTTPS test error: $_" -Level Error
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
            "https://login.microsoftonline.com",
            "https://login.windows.net",
            "https://login.microsoft.com",
            "https://logincert.microsoftonline.com",
            "https://graph.microsoft.com",
            "https://sts.windows.net",
            "https://login.live.com",
            "https://aadcdn.msauth.net",                 # CDN for loging prompt rendering              
            "https://aadcdn.msftauthimages.net",         # CDN for loging prompt rendering
            "https://enterpriseregistration.windows.net",
            "https://device.login.microsoftonline.com",  # Device Auth
            "https://certauth.login.microsoftonline.com" # CBA AuthN

        ),
        [int]$Timeout = 15
    )

    $allTestsPassed = $true

    foreach ($url in $Endpoints) {
        try {
            Write-Log -Message "Testing connectivity to $url ..." -Level "INFO"
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $Timeout

            if ($response.StatusCode -eq 200) {
                Write-Log -Message "Successfully connected to $url" -Level "SUCCESS"                
            }                    
        } 
        catch [System.Net.WebException] {
            if ($_.Exception.Response -and ($_.Exception.Response.StatusCode -ge 400 -and $_.Exception.Response.StatusCode -lt 500)) {
                Write-Log -Message "Successfully connected to '$url'. Received HTTP status code: $($_.Exception.Response.StatusCode) ($($_.Exception.Response.StatusDescription)). This is expected for some endpoints." -Level "WARNING"
            }
            else {
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
# Function: Load-GSAEndpoints
# This function loads the JSON content from the registry, extracts channels, edge addresses, and diagnostic URIs.
#
function Load-GSAEndpoints {
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
Write-Log "========= GSA Client Connectivity Checker Started ========="

# Try to load the GSA client configuration from the registry
$gsaEndpoints = Load-GSAEndpoints -RegistryValueName "ForwardingProfile"

if (-Not $gsaEndpoints) { exit }

$gsaMainEndpointAddrs = $gsaEndpoints.MainEndpoints
$DiagnosticUris = $gsaEndpoints.DiagnosticUris

# Define a hashtable of tests
$tests = [ordered]@{
    "Basic Internet connectivity" = { Test-InternetConnectivity }
    "Proxy Detection"             = { Test-ProxyDetection }
    "DNS Resolution"              = { param($param1) Test-DnsResolution -fqdnList $param1 }
    "Entra ID Connectivity"       = { Test-EntraIDConnectivity }
    "TLS Connectivity"            = { param($param1) Test-TLSConnection -fqdnList $param1 }
    "mTLS Connectivity"           = { param($param1) Test-mTLSConnection -fqdnList $param1 }
    "Diagnostics Connectivity"    = { param($param1) Test-DiagnosticUris -DiagnosticUris $param1 }    
}

# table to hold the Parameters for each test, that need Parameters
$testParams = [ordered]@{
    "DNS Resolution"   = @{ param1 = $gsaMainEndpointAddrs }
    "TLS Connectivity" = @{ param1 = $gsaMainEndpointAddrs }
    "mTLS Connectivity" = @{ param1 = $gsaMainEndpointAddrs }
    "Diagnostics Connectivity" = @{ param1 = $DiagnosticUris }
}

# Run all tests
foreach ($testName in $tests.Keys) 
{
    Write-Log -Message "===== Executing: $testName =========" -Level "INFO"
    #$result = & $tests[$testName]  # Invoke function dynamically

    $scriptBlock = $tests[$testName]
    $params = $testParams[$testName]

    if ($params) {
        $result = & $scriptBlock @params
    } else {
        $result = & $scriptBlock
    }

    if ($result) 
    {
        Write-Log "===== $testName : PASSED =========" "SUCCESS"
    } else 
    {
        Write-Log "===== $testName : FAILED =========" "ERROR"        
    }
}

Write-Log "========= GSA Connectivity check Completed ========="

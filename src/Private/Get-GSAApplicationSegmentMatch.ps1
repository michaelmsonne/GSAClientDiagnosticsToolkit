#
# Function: Get-GSAApplicationSegmentMatch
# Evaluates a Private Access application's Graph application segments against a target address/port/protocol.
# Example: Get-GSAApplicationSegmentMatch -Segments $segments -FQDNorIP 'fileserver.contoso.com' -InputType FQDN -Port 445 -Protocol TCP
#
function Get-GSAApplicationSegmentMatch {
    param (
        [object[]]$Segments,
        [string]$FQDNorIP,
        [ValidateSet("IP", "FQDN")]
        [string]$InputType,
        [int]$Port,
        [string]$Protocol
    )

    $result = [PSCustomObject]@{
        AddressMatched  = $false
        PortMatched     = $false
        ProtocolMatched = $false
    }

    if ($InputType -eq 'FQDN') {
        $candidates = @($Segments) | Where-Object { $_.destinationType -eq 'fqdn' }
    }
    else {
        $candidates = @($Segments) | Where-Object { $_.destinationType -match '^ip' }
    }

    foreach ($segment in $candidates) {
        $addressMatch = $false

        if ($InputType -eq 'FQDN') {
            $destinationHost = $segment.destinationHost
            if ($destinationHost -and ($FQDNorIP -eq $destinationHost -or $destinationHost -match '^\*\.')) {
                $addressMatch = $true
            }
        }
        else {
            switch ($segment.destinationType) {
                'ip' {
                    if ($FQDNorIP -eq $segment.destinationHost) { $addressMatch = $true }
                }
                'ipRange' {
                    $bounds = $segment.destinationHost -split '\.\.'
                    if ($bounds.Count -eq 2) {
                        $startBytes = [System.Net.IPAddress]::Parse($bounds[0]).GetAddressBytes()
                        [Array]::Reverse($startBytes)
                        $endBytes = [System.Net.IPAddress]::Parse($bounds[1]).GetAddressBytes()
                        [Array]::Reverse($endBytes)
                        $addressMatch = Test-GSAIPInRange -Start ([BitConverter]::ToUInt32($startBytes, 0)) -End ([BitConverter]::ToUInt32($endBytes, 0)) -IPAddress $FQDNorIP
                    }
                }
                'ipRangeCidr' {
                    $cidrParts = $segment.destinationHost -split '/'
                    if ($cidrParts.Count -eq 2) {
                        $baseBytes = [System.Net.IPAddress]::Parse($cidrParts[0]).GetAddressBytes()
                        [Array]::Reverse($baseBytes)
                        $baseIP = [BitConverter]::ToUInt32($baseBytes, 0)
                        $mask = -bnot ([uint32]([math]::Pow(2, (32 - [int]$cidrParts[1])) - 1))
                        $startIP = $baseIP -band $mask
                        $endIP = $startIP -bor (-bnot $mask)
                        $addressMatch = Test-GSAIPInRange -Start $startIP -End $endIP -IPAddress $FQDNorIP
                    }
                }
            }
        }

        if (-not $addressMatch) { continue }
        $result.AddressMatched = $true

        if (-not (Test-GSAPortInRange -Ports (ConvertTo-GSAPortRange -Ranges $segment.ports) -Port $Port)) { continue }
        $result.PortMatched = $true

        if ($segment.protocol -match "\b$Protocol\b") {
            $result.ProtocolMatched = $true
            break
        }
    }

    return $result
}

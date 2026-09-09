#
# Function: Test-GSAIsPrivateIPv4
# Checks whether an IPv4 address falls within an RFC1918 private range (10.0.0.0/8,
# 172.16.0.0/12, 192.168.0.0/16) or the loopback range (127.0.0.0/8).
# Example: Test-GSAIsPrivateIPv4 -IPAddress '192.168.1.1'   # returns $true
#
function Test-GSAIsPrivateIPv4 {
    param (
        [string]$IPAddress
    )

    try {
        $bytes = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
    }
    catch {
        return $false
    }
    if ($bytes.Count -ne 4) { return $false }

    switch ($bytes[0]) {
        10 { return $true }
        127 { return $true }
        172 { return ($bytes[1] -ge 16 -and $bytes[1] -le 31) }
        192 { return ($bytes[1] -eq 168) }
        default { return $false }
    }
}

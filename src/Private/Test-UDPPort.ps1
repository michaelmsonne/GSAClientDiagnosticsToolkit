#
# Function: Test-UDPPort
# helper code to test UDP port connectivity
#
function Test-UDPPort
{
	param (
		[string]$IPAddress,
		[int]$Port = 53,
		[int]$Timeout = 5000
	)

	try
    {
		$udpClient = [System.Net.Sockets.UdpClient]::new()
		$udpClient.Connect($IPAddress, $Port)
		Write-Log -Message "Testing UDP connectivity to $IPAddress on port $Port" -Level "INFO" -Color Cyan

		# Construct a simple DNS query for nxdomain.com to minimize data transmission
		$query = [byte[]](0xAA, 0xAA, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x08, 0x6e, 0x78, 0x64, 0x6f, 0x6d, 0x61, 0x69, 0x6e, 0x03, 0x63, 0x6f,
			0x6d, 0x00, 0x00, 0x01, 0x00, 0x00)
		$udpClient.Send($query, $query.Length)

		# blocking receive until we get a response or timeout
		$receiveTask = $udpClient.ReceiveAsync()
		if ($receiveTask.Wait($Timeout))
        {
			$receiveTask.Result | Out-Null
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

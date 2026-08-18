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

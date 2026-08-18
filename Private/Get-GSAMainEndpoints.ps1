function Get-GSAMainEndpoints {
    param ([object]$jsonContent)

    if (-Not $jsonContent.policy.channels) {
        Write-Log "No channels found in JSON file." "WARNING"
        return @()
    }

    $channelEndpoints = @()

    foreach ($channel in $jsonContent.policy.channels) {
        $edges         = @()
        $channelName   = $channel.name
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

        $channelEndpoints += [PSCustomObject]@{
            ChannelName   = $channelName
            EdgeAddresses = $edges
            DiagnosticUri = $diagnosticUri
        }
    }

    Write-Log "Extracted $($channelEndpoints.Count) channel entries with endpoint data."
    return $channelEndpoints
}

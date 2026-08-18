function Test-grpcProxy {
    try {
        $machineGrpcProxy = [System.Environment]::GetEnvironmentVariable("grpc_proxy", "Machine")
        $userGrpcProxy    = [System.Environment]::GetEnvironmentVariable("grpc_proxy", "User")

        if ($machineGrpcProxy) {
            Write-Log -Message "Machine-level grpc_proxy variable is set to: $machineGrpcProxy" -Level "WARNING"
        } else {
            Write-Log -Message "Machine-level grpc_proxy variable is not set." -Level "INFO"
        }

        if ($userGrpcProxy) {
            Write-Log -Message "User-level grpc_proxy variable is set to: $userGrpcProxy" -Level "WARNING"
        } else {
            Write-Log -Message "User-level grpc_proxy variable is not set." -Level "INFO"
        }

        return ($machineGrpcProxy -and $userGrpcProxy)
    }
    catch {
        Write-Log -Message "Error checking grpc_proxy environment variables: $_" -Level "ERROR"
        return $false
    }
}

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
    $currentIndex  = $levels.IndexOf($script:LogLevel.ToUpper())
    $messageIndex  = $levels.IndexOf($Level.ToUpper())

    [System.Threading.Monitor]::Enter($script:LogLockObject)
    try {
        $timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"

        if ($messageIndex -le $currentIndex -or $Level -eq "SUCCESS") {
            $color = switch ($Level) {
                "ERROR"   { "Red" }
                "WARNING" { "Yellow" }
                "INFO"    { "Gray" }
                "DEBUG"   { "Cyan" }
                "SUCCESS" { "Green" }
            }
            Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
        }

        if ($script:LogFilePath) {
            $fileStream   = [System.IO.File]::Open($script:LogFilePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            $streamWriter = New-Object System.IO.StreamWriter($fileStream)
            try {
                $streamWriter.WriteLine($logMessage)
            }
            finally {
                $streamWriter.Close()
                $fileStream.Close()
            }
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($script:LogLockObject)
    }
}

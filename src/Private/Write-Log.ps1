# 
# Function: Logging with Console Output (thread safe)
# 
# This function will log messages to the console and a log file.
# It uses a global lock object to ensure thread safety.
# Input parameters:
# - Message: The message to log.
# - Level: The log level (ERROR, WARNING, INFO, DEBUG, SUCCESS). Default is INFO.
# - Color: Overrides the level's default console color (used for custom-formatted rows/tables).
# - NoPrefix: Skips the "[timestamp] [Level]" prefix (used for pre-formatted lines like table rows).
function Write-Log
{
	param (
		[string]$Message,
		[ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
		[string]$Level = "INFO",
		[System.ConsoleColor]$Color,
		[switch]$NoPrefix
	)

	# Determine the index of the current log level and the message's log level for filtering purposes.
	$levels = @("ERROR", "WARNING", "INFO", "DEBUG")

	# Get the numeric index of the current log level and the message's log level.
	$currentIndex = $levels.IndexOf($script:LogLevel.ToUpper())
	$messageIndex = $levels.IndexOf($Level.ToUpper())

	# Acquire the global lock to ensure thread-safe logging.
	[System.Threading.Monitor]::Enter($script:LogLockObject)
	try
    {
		# Generate the timestamp and construct the log message with or without the prefix.
		$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		$logMessage = if ($NoPrefix) { $Message } else { "[$timestamp] [$Level] $Message" }

		# Check if the message should be logged based on the current log level and the message's log level.
		# The same filter applies to the console and the log file, so the file mirrors what the console shows.
		if ($messageIndex -le $currentIndex -or $Level -eq "SUCCESS")
        {
			$consoleColor = if ($PSBoundParameters.ContainsKey('Color')) {
				$Color
			}
			else
            {
				switch ($Level)
                {
					"ERROR" { "Red" }
					"WARNING" { "Yellow" }
					"INFO" { "Gray" }
					"DEBUG" { "Cyan" }
					"SUCCESS" { "Green" }
				}
			}
			Write-Host $logMessage -ForegroundColor $consoleColor

			# Write the log message to the log file if a log file path is specified.
			if ($script:LogFilePath)
            {
				$fileStream = [System.IO.File]::Open($script:LogFilePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
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
		}
	}
	finally
    {
		[System.Threading.Monitor]::Exit($script:LogLockObject)
	}
}

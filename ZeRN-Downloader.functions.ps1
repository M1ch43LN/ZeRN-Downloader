# Log-Level
[int]$log_info = 1
[int]$log_warning = 2
[int]$log_error = 3
[int]$log_debug = 0

function Write-Log {
    param (
        [string]$LogText = "",
        [int]$LogType = $log_info
    )

    $timestamp = Get-Date -Format "dd.MM.yyyy hh:mm:ss"

    $LogText = "$timestamp - [$LogType] - $LogText"

    Switch($LogType) {        
        $log_warning {
            if ($log_level -le $log_warning) { Write-Host $LogText -ForegroundColor Yellow }
        }
        $log_error {
            if ($log_level -le $log_error) { Write-Host $LogText -ForegroundColor Red }
        }
        $log_debug {
            if ($log_level -eq $log_debug) { Write-Host $LogText -ForegroundColor Cyan }
        }
        Default {
            if ($log_level -le $log_info) { Write-Host $LogText }
        }
    }    
}

function Write-Info {
    param (
        [string]$LogText = ""
    )
    Write-Log $LogText $log_info
}

function Write-Warning {
    param (
        [string]$LogText = ""
    )
    Write-Log $LogText $log_warning
}

function Write-Error {
    param (
        [string]$LogText = ""
    )
    Write-Log $LogText $log_error
}

function Write-Debug {
    param (
        [string]$LogText = ""
    )
    Write-Log $LogText $log_debug
}

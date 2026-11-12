###############################################################################
# ZeRN-Downloader - Funktionen
#
# Kompatibel mit Windows PowerShell 5.1 und PowerShell 7.
###############################################################################

# Log-Level
[int]$log_debug = 0
[int]$log_info = 1
[int]$log_warning = 2
[int]$log_error = 3

# Standard, falls in der Konfiguration nicht gesetzt (wird dort überschrieben)
[int]$log_level = $log_info

# API
$api_baseurl = "https://api.erechnung.niedersachsen.de"
$useragent = "ZeRN-Downloader/1.5 (https://github.com/M1ch43LN/ZeRN-Downloader)"

# Timeout je API-Aufruf in Sekunden (in der Konfiguration überschreibbar)
$api_timeout = 120

# Workflow-Skript (leer = keines) und dessen Timeout in Sekunden (0 = unbegrenzt)
$workflowscript = ""
$workflow_timeout = 3600

# Verzeichnis für Manifeste (leer = Unterverzeichnis "manifest" im Log-Verzeichnis)
$files_manifest = ""

# Aktuelles Token (AccessToken, RefreshToken, ExpiresAt)
$zern_token = $null

###############################################################################
# Protokollierung
###############################################################################

function Write-Log {
    param (
        [string]$LogText = "",
        [int]$LogType = $log_info
    )

    $timestamp = Get-Date -Format "dd.MM.yyyy HH:mm:ss"

    Switch ($LogType) {
        $log_warning {
            if ($log_level -le $log_warning) { Write-Host "$timestamp - [WARNUNG] - $LogText" -ForegroundColor Yellow }
        }
        $log_error {
            if ($log_level -le $log_error) { Write-Host "$timestamp - [FEHLER]  - $LogText" -ForegroundColor Red }
        }
        $log_debug {
            if ($log_level -eq $log_debug) { Write-Host "$timestamp - [DEBUG]   - $LogText" -ForegroundColor Cyan }
        }
        Default {
            if ($log_level -le $log_info) { Write-Host "$timestamp - [INFO]    - $LogText" }
        }
    }
}

function Write-Info {
    param ([string]$LogText = "")
    Write-Log $LogText $log_info
}

function Write-Warning {
    param ([string]$LogText = "")
    Write-Log $LogText $log_warning
}

function Write-Error {
    param ([string]$LogText = "")
    Write-Log $LogText $log_error
}

function Write-Debug {
    param ([string]$LogText = "")
    Write-Log $LogText $log_debug
}

# Liefert den HTTP-Statuscode aus einem Fehler von Invoke-WebRequest (PS 5.1 und 7), sonst 0
function Get-HttpStatusCode {
    param ($ErrorRecord)
    try {
        if ($null -ne $ErrorRecord.Exception.Response) {
            return [int]$ErrorRecord.Exception.Response.StatusCode
        }
    } catch { }
    return 0
}

# Lesbare Fehlermeldung inkl. HTTP-Status und ProblemDetails der API
function Format-ApiError {
    param ($ErrorRecord)
    $text = "$($ErrorRecord.Exception.Message)"
    $status = Get-HttpStatusCode $ErrorRecord
    if ($status -ne 0) {
        $text = "HTTP $status - $text"
    }
    if ($null -ne $ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $text = "$text | $($ErrorRecord.ErrorDetails.Message -replace '\s+', ' ')"
    }
    return $text
}

###############################################################################
# Dateien
###############################################################################

# Legt ein Verzeichnis an, falls es konfiguriert ist und noch nicht existiert
function Initialize-Directory {
    param ([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        Write-Info "Verzeichnis '$Path' angelegt."
    }
}

# Schreibt Bytes unverändert in eine Datei. Zuerst in eine .part-Datei, dann
# Umbenennen, damit nachgelagerte Prozesse nie halbe Dateien sehen.
function Save-Bytes {
    param (
        [string]$Path,
        [byte[]]$Bytes
    )
    $tmp = "$Path.part"
    try {
        [System.IO.File]::WriteAllBytes($tmp, $Bytes)
        if ([System.IO.File]::Exists($Path)) {
            # [NullString]::Value statt $null, sonst übergibt PowerShell "" (= Fehler)
            [System.IO.File]::Replace($tmp, $Path, [NullString]::Value)
        } else {
            [System.IO.File]::Move($tmp, $Path)
        }
    } catch {
        if ([System.IO.File]::Exists($tmp)) { [System.IO.File]::Delete($tmp) }
        throw
    }
}

# Macht aus einem von außen gelieferten Dateinamen einen sicheren Dateinamen
# (keine Pfadanteile, keine ungültigen Zeichen)
function Get-SafeFileName {
    param (
        [string]$FileName,
        [string]$Fallback = "attachment.bin"
    )
    if ([string]::IsNullOrWhiteSpace($FileName)) { return $Fallback }
    $name = $FileName -replace '[\\/]', '_'
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        $name = $name.Replace([string]$c, "_")
    }
    $name = $name.Trim().TrimStart('.')
    if ([string]::IsNullOrWhiteSpace($name)) { return $Fallback }
    if ($name.Length -gt 150) {
        $ext = [System.IO.Path]::GetExtension($name)
        if ($ext.Length -gt 20) { $ext = "" }
        $name = $name.Substring(0, 150 - $ext.Length) + $ext
    }
    return $name
}

# Ermittelt die XML-Syntax anhand des Namespaces des Wurzelelements.
# Rückgabe: "CII", "UBL" (Invoice und CreditNote) oder $null
function Get-XmlSyntax {
    param ([byte[]]$Bytes)

    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null

    $stream = New-Object System.IO.MemoryStream(, $Bytes)
    try {
        $reader = [System.Xml.XmlReader]::Create($stream, $settings)
        try {
            [void]$reader.MoveToContent()
            $ns = $reader.NamespaceURI
            $name = $reader.LocalName
        } finally {
            $reader.Close()
        }
    } catch {
        Write-Warning "XML konnte nicht gelesen werden: $($_.Exception.Message)"
        return $null
    } finally {
        $stream.Dispose()
    }

    Write-Debug "XML-Wurzelelement: {$ns}$name"
    switch ($ns) {
        "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" { return "CII" }
        "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"      { return "UBL" }
        "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2"   { return "UBL" }
    }
    return $null
}

###############################################################################
# API
###############################################################################

# Sendet einen Request und liefert den Body als unveränderte Bytes
function Invoke-ApiRaw {
    param (
        [string]$Method = "Get",
        [string]$Path,
        [hashtable]$Headers = @{},
        [object]$Body = $null
    )
    $params = @{
        Method          = $Method
        Uri             = "$api_baseurl$Path"
        Headers         = $Headers
        UserAgent       = $useragent
        UseBasicParsing = $true
        TimeoutSec      = $api_timeout
        ErrorAction     = "Stop"
    }
    if ($null -ne $Body) {
        $params.Body = $Body
        $params.ContentType = "application/json; charset=utf-8"
    }
    Write-Debug "API: $($Method.ToUpper()) $api_baseurl$Path"
    $response = Invoke-WebRequest @params
    if ($null -eq $response.RawContentStream) { return , [byte[]]@() }
    return , $response.RawContentStream.ToArray()
}

# Dekodiert UTF-8-JSON (unabhängig vom Charset-Header, PS 5.1 rät sonst ISO-8859-1)
function ConvertFrom-JsonBytes {
    param ([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return $null }
    $text = [System.Text.Encoding]::UTF8.GetString($Bytes)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}

# Übernimmt die Token-Antwort der API
function Set-ApiToken {
    param ($AuthData)
    if ($null -eq $AuthData -or [string]::IsNullOrWhiteSpace($AuthData.accessToken)) {
        throw "Die API hat kein Access Token geliefert."
    }
    $expires_in = 0
    if ($null -ne $AuthData.expiresIn) { $expires_in = [int]$AuthData.expiresIn }
    # Sicherheitsabstand: 60 s, bei sehr kurzen Laufzeiten die Hälfte
    if ($expires_in -gt 120) { $valid = $expires_in - 60 } else { $valid = [Math]::Max($expires_in / 2, 1) }

    $script:zern_token = [pscustomobject]@{
        AccessToken  = $AuthData.accessToken
        RefreshToken = $AuthData.refreshToken
        ExpiresAt    = (Get-Date).AddSeconds($valid)
    }
    Write-Debug "Access Token gültig bis $($script:zern_token.ExpiresAt.ToString('HH:mm:ss')) (expiresIn: $expires_in s)"
}

# Anmeldung mit Benutzername/Passwort
function Connect-Api {
    $json = @{ userName = $api_username; password = $api_password } | ConvertTo-Json -Compress
    $body = [System.Text.Encoding]::UTF8.GetBytes($json)
    $bytes = Invoke-ApiRaw -Method Post -Path "/api/accesstoken/create" -Headers @{ Accept = "application/json" } -Body $body
    Set-ApiToken (ConvertFrom-JsonBytes $bytes)
}

# Stellt sicher, dass ein gültiges Token vorliegt (Refresh, notfalls neue Anmeldung)
function Update-ApiToken {
    param ([switch]$Force)

    if ($null -eq $script:zern_token) {
        Connect-Api
        return
    }
    if (-not $Force -and (Get-Date) -lt $script:zern_token.ExpiresAt) { return }

    if (-not [string]::IsNullOrWhiteSpace($script:zern_token.RefreshToken)) {
        try {
            Write-Debug "Access Token wird erneuert..."
            $json = @{ refreshToken = $script:zern_token.RefreshToken } | ConvertTo-Json -Compress
            $body = [System.Text.Encoding]::UTF8.GetBytes($json)
            $bytes = Invoke-ApiRaw -Method Post -Path "/api/accesstoken/refresh" -Headers @{ Accept = "application/json" } -Body $body
            Set-ApiToken (ConvertFrom-JsonBytes $bytes)
            Write-Info "Access Token erneuert."
            return
        } catch {
            Write-Warning "Erneuern des Access Tokens fehlgeschlagen, neue Anmeldung: $(Format-ApiError $_)"
        }
    }
    Connect-Api
    Write-Info "Neu an der API angemeldet."
}

# Authentifizierter API-Aufruf. Liefert die Antwort als Bytes.
# Erneuert das Token vorab bei Ablauf und wiederholt einmalig nach HTTP 401.
function Invoke-Api {
    param (
        [string]$Method = "Get",
        [string]$Path
    )
    Update-ApiToken
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        # Accept application/json wie in Version 1.x: so liefert die API auch XML aus
        $headers = @{
            Accept        = "application/json"
            Authorization = "Bearer $($script:zern_token.AccessToken)"
        }
        try {
            return , (Invoke-ApiRaw -Method $Method -Path $Path -Headers $headers)
        } catch {
            if ($attempt -eq 1 -and (Get-HttpStatusCode $_) -eq 401) {
                Write-Warning "HTTP 401, Token wird erneuert und der Aufruf wiederholt..."
                Update-ApiToken -Force
                continue
            }
            throw
        }
    }
}

function Invoke-ApiJson {
    param (
        [string]$Method = "Get",
        [string]$Path
    )
    return (ConvertFrom-JsonBytes (Invoke-Api -Method $Method -Path $Path))
}

###############################################################################
# Manifest und Workflow
###############################################################################

# Manifest-Eintrag für eine Rechnung aus der Rechnungsliste
function New-ManifestEntry {
    param ($Invoice)
    $received = $Invoice.received
    if ($received -is [datetime]) { $received = $received.ToString("o") }
    return [ordered]@{
        InvoiceId           = [string]$Invoice.id
        Received            = [string]$received
        SenderName          = [string]$Invoice.sender.name
        SenderEmail         = [string]$Invoice.sender.emailAddress
        SenderInvoiceNumber = [string]$Invoice.senderInvoiceNumber
        Scheme              = $Invoice.scheme
        TypeCode            = $Invoice.typeCode
        Syntax              = $null
        XmlFile             = $null
        ValidationFile      = $null
        Attachments         = (New-Object System.Collections.ArrayList)
        Marked              = $false
        Success             = $false
    }
}

# Schreibt das Manifest eines Laufs als JSON (UTF-8 ohne BOM) und liefert den Pfad
function Save-Manifest {
    param (
        [string]$Directory,
        [datetime]$Started,
        [int]$ExitCode,
        [switch]$NoMark,
        $Invoices
    )
    Initialize-Directory $Directory
    $manifest = [ordered]@{
        Version          = $useragent
        Started          = $Started.ToString("o")
        Finished         = (Get-Date).ToString("o")
        NoMark           = [bool]$NoMark
        DownloadExitCode = $ExitCode
        InvoiceCount     = $Invoices.Count
        SuccessCount     = @($Invoices | Where-Object { $_.Success }).Count
        Invoices         = $Invoices
    }
    $json = ConvertTo-Json -InputObject $manifest -Depth 6
    $file = Join-Path $Directory ("{0}.json" -f $Started.ToString("yyyy-MM-dd_HHmmss"))
    Save-Bytes -Path $file -Bytes ((New-Object System.Text.UTF8Encoding($false)).GetBytes($json))
    return $file
}

# Startet das Workflow-Skript in einem eigenen PowerShell-Prozess, wartet auf das
# Ende und übernimmt dessen Ausgabe ins Protokoll. Rückgabe: $true bei Exit-Code 0.
function Invoke-Workflow {
    param (
        [string]$Script,
        [int]$ExitCode,
        [string]$ManifestPath,
        [int]$TimeoutSec = 0
    )
    if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
        Write-Error "Workflow-Skript '$Script' nicht gefunden."
        return $false
    }

    # Gleiche PowerShell wie der Downloader (powershell.exe bzw. pwsh)
    $exe = (Get-Process -Id $PID).Path
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ExitCode {1} -ManifestPath "{2}"' -f $Script, $ExitCode, $ManifestPath
    $out_file = "$ManifestPath.workflow-stdout.txt"
    $err_file = "$ManifestPath.workflow-stderr.txt"

    Write-Info "Starte Workflow-Skript '$Script'..."
    Write-Debug "Aufruf: $exe $arguments"
    $started = Get-Date
    try {
        $process = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -NoNewWindow `
            -RedirectStandardOutput $out_file -RedirectStandardError $err_file -ErrorAction Stop
        # Handle merken, sonst liefert PS 5.1 nach dem Ende keinen ExitCode
        $null = $process.Handle
        if ($TimeoutSec -gt 0) {
            $finished = $process.WaitForExit($TimeoutSec * 1000)
        } else {
            $process.WaitForExit()
            $finished = $true
        }
        if (-not $finished) {
            Write-Error "Workflow-Skript nach $TimeoutSec s abgebrochen (Timeout)."
            try { $process.Kill() } catch { }
            $process.WaitForExit(10000) | Out-Null
        }
        $process.WaitForExit()
    } catch {
        Write-Error "Workflow-Skript konnte nicht gestartet werden: $($_.Exception.Message)"
        return $false
    }

    # Ausgabe des Workflow-Skripts ins Protokoll übernehmen
    foreach ($f in @($out_file, $err_file)) {
        if (Test-Path -LiteralPath $f) {
            # Kindprozess schreibt in der Konsolen-Codepage (PS 5.1), nicht UTF-8
            $text = [Console]::OutputEncoding.GetString([System.IO.File]::ReadAllBytes($f))
            foreach ($line in ($text -split "`r?`n" | Where-Object { $_ -ne "" })) {
                if ($f -eq $err_file) { Write-Error "[Workflow] $line" } else { Write-Info "[Workflow] $line" }
            }
            Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        }
    }

    $duration = [int]((Get-Date) - $started).TotalSeconds
    if (-not $finished) { return $false }
    if ($process.ExitCode -ne 0) {
        Write-Error "Workflow-Skript beendet mit Exit-Code $($process.ExitCode) nach $duration s."
        return $false
    }
    Write-Info "Workflow-Skript erfolgreich beendet nach $duration s."
    return $true
}

###############################################################################
# ZeRN-Downloader
#
# Skript zum automatisierten Herunterladen von eRechnungen aus dem Zentralen
# eRechnungseingang Niedersachsen (ZeRN).
#
# Infos: https://github.com/M1ch43LN/ZeRN-Downloader
#
# Exit-Codes (für die Aufgabenplanung, Aufruf mit powershell.exe -File):
#   0 = alles OK
#   1 = Abbruch (Konfiguration, Verzeichnisse, Anmeldung, Rechnungsliste)
#   2 = mindestens eine Rechnung fehlerhaft (bleibt im ZeRN auf "neu")
#   3 = Workflow-Skript fehlgeschlagen (nicht gefunden, Exit-Code <> 0, Timeout)
#
# Parameter:
#   -NoMark  Testmodus: Dateien werden geladen, die Rechnungen aber NICHT
#            als heruntergeladen markiert (bleiben im ZeRN auf "neu")
#
# Historie:
#
# 2025-01-27 Initiale Version
# 2025-02-03 Trennung der Verzeichnisse nach XML-Syntax (CII/UBL) möglich
# 2026-11-12 1.2: Fehlerkorrekturen: Anhänge je Rechnung, kein veralteter
#            Validierungsreport, 24h-Zeitstempel, Exit-Codes
# 2026-11-12 1.3: Token-Erneuerung (Refresh, Retry bei 401), bytegenaues
#            Speichern von Rechnung und Validierungsreport, Syntax-Erkennung
#            per Namespace (inkl. UBL-CreditNote), Anhänge über
#            /document-Endpunkt mit sicheren Dateinamen, Rechnungs-XML wird
#            nicht mehr doppelt als Anhang gespeichert, atomisches Schreiben,
#            Verzeichnisse werden angelegt, TLS 1.2, kein Token im Log
# 2026-11-12 1.4: Sofortige Statusausgabe beim Start, Timeout je API-Aufruf,
#            keine Fortschrittsanzeige (bremst Windows PowerShell 5.1)
# 2026-11-12 1.5: Manifest je Lauf (JSON) und optionales Workflow-Skript
#            ($workflowscript), das nach Läufen mit neuen Rechnungen startet
#
###############################################################################

param (
    [switch]$NoMark
)

# Funktionen laden
. "$PSScriptRoot\ZeRN-Downloader.functions.ps1"

# Konfiguration laden
$config_file = Join-Path $PSScriptRoot "ZeRN-Downloader.config.ps1"
if (-not (Test-Path -LiteralPath $config_file)) {
    Write-Error "Konfigurationsdatei '$config_file' nicht gefunden. Vorlage: ZeRN-Downloader.config-sample.ps1"
    exit 1
}
. $config_file

# Fortschrittsanzeige von Invoke-WebRequest abschalten (in PS 5.1 sehr langsam)
$ProgressPreference = "SilentlyContinue"

# TLS 1.2 erzwingen (Windows PowerShell 5.1 nutzt je nach .NET-Konfiguration sonst ältere Protokolle)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Exit-Code, siehe oben
$exit_code = 0

# Verzeichnisse prüfen bzw. anlegen
try {
    Initialize-Directory $files_log
    Initialize-Directory $files_xml
    Initialize-Directory $files_xml_cii
    Initialize-Directory $files_xml_ubl
    Initialize-Directory $files_validation
    Initialize-Directory $files_attachment
} catch {
    Write-Error "Verzeichnis konnte nicht angelegt werden: $($_.Exception.Message)"
    exit 1
}

# Protokoll starten
$log_date = Get-Date -Format "yyyy-MM-dd"
$log_file = Join-Path $files_log "$log_date.log"
Start-Transcript -Path $log_file -Append | Out-Null

Write-Info "ZeRN-Downloader gestartet (PowerShell $($PSVersionTable.PSVersion), Protokoll: $log_file)"

Write-Debug "Verzeichnis XML-Dateien (unbekannte Syntax): $files_xml"
Write-Debug "Verzeichnis XML-Dateien CII: $files_xml_cii"
Write-Debug "Verzeichnis XML-Dateien UBL: $files_xml_ubl"
Write-Debug "Verzeichnis Validierungsreports: $files_validation"
Write-Debug "Verzeichnis Attachments: $files_attachment"

$load_validation = -not [string]::IsNullOrWhiteSpace($files_validation)
if ($NoMark) { Write-Warning "Testmodus (-NoMark): Rechnungen werden nicht als heruntergeladen markiert." }

$load_attachments = -not [string]::IsNullOrWhiteSpace($files_attachment)

# Manifest und Workflow
if ([string]::IsNullOrWhiteSpace($files_manifest)) { $files_manifest = Join-Path $files_log "manifest" }
$run_started = Get-Date
$manifest_invoices = New-Object System.Collections.ArrayList
$use_workflow = -not [string]::IsNullOrWhiteSpace($workflowscript)
if ($use_workflow) {
    Write-Debug "Workflow-Skript: $workflowscript (Timeout $workflow_timeout s)"
    if (-not (Test-Path -LiteralPath $workflowscript -PathType Leaf)) {
        Write-Warning "Workflow-Skript '$workflowscript' nicht gefunden."
    }
}

# Anmeldung an API
Write-Info "Anmeldung an $api_baseurl als '$api_username' (Timeout $api_timeout s)..."
try {
    Update-ApiToken
    Write-Info "Anmeldung an API erfolgreich."
} catch {
    Write-Error "Fehler bei der Anmeldung: $(Format-ApiError $_)"
    Stop-Transcript | Out-Null
    exit 1
}

# Liste neuer Rechnungen holen
Write-Info "Lade Liste neuer Rechnungen..."
try {
    $response_invoices = Invoke-ApiJson -Path "/api/invoice/new"
} catch {
    Write-Error "Fehler beim Laden der Rechnungsliste: $(Format-ApiError $_)"
    Stop-Transcript | Out-Null
    exit 1
}

$invoices = @($response_invoices | Where-Object { $null -ne $_ })
Write-Info "$($invoices.Count) neue Rechnung(en) vorhanden..."

foreach ($invoice in $invoices) {
    $invoice_id = [string]$invoice.id
    $success = $true

    # Eintrag für das Manifest (Hashtable = Referenz, wird unten fortgeschrieben)
    $entry = New-ManifestEntry $invoice
    [void]$manifest_invoices.Add($entry)

    Write-Info "Verarbeite Rechnung ID '$invoice_id'..."
    Write-Debug "Empfangen: $($invoice.received)"
    Write-Debug "Absender: $($invoice.sender.name)"
    Write-Debug "Rechnungsnummer: $($invoice.senderInvoiceNumber)"
    Write-Debug "Schema: $($invoice.scheme), TypeCode: $($invoice.typeCode), Status: $($invoice.status)"

    # Schutz gegen manipulierte IDs im Dateinamen
    $guid = [guid]::Empty
    if (-not [guid]::TryParse($invoice_id, [ref]$guid)) {
        Write-Error "Ungültige Rechnungs-ID '$invoice_id', Rechnung wird übersprungen."
        $exit_code = 2
        continue
    }

    # XML-Datei der Rechnung herunterladen und unverändert speichern
    try {
        $xml_bytes = Invoke-Api -Path "/api/invoice/$invoice_id/xml"
        if ($null -eq $xml_bytes -or $xml_bytes.Length -eq 0) {
            throw "Die API hat eine leere Rechnung geliefert."
        }

        $entry.Syntax = Get-XmlSyntax $xml_bytes
        switch ($entry.Syntax) {
            "CII" {
                Write-Debug "XML-Syntax: CII"
                $file_xml = Join-Path $files_xml_cii "$invoice_id.xml"
            }
            "UBL" {
                Write-Debug "XML-Syntax: UBL"
                $file_xml = Join-Path $files_xml_ubl "$invoice_id.xml"
            }
            default {
                Write-Warning "XML-Syntax nicht erkannt."
                $file_xml = Join-Path $files_xml "$invoice_id.xml"
            }
        }

        Write-Info "Speichere '$file_xml'"
        Save-Bytes -Path $file_xml -Bytes $xml_bytes
        $entry.XmlFile = $file_xml
    } catch {
        Write-Error "Fehler beim Laden/Speichern der XML-Rechnung ID $invoice_id : $(Format-ApiError $_)"
        $exit_code = 2
        # Ohne Rechnung keine weiteren Schritte und keine Markierung
        continue
    }

    # Validierungsreport laden und unverändert speichern
    if ($load_validation) {
        try {
            Write-Info "Lade Validierungsreport ID '$invoice_id'..."
            $validation_bytes = Invoke-Api -Path "/api/invoice/$invoice_id/validationreport"
            if ($null -eq $validation_bytes -or $validation_bytes.Length -eq 0) {
                throw "Die API hat einen leeren Validierungsreport geliefert."
            }
            $file_validation = Join-Path $files_validation "$invoice_id.xml"
            Write-Info "Speichere '$file_validation'"
            Save-Bytes -Path $file_validation -Bytes $validation_bytes
            $entry.ValidationFile = $file_validation
        } catch {
            Write-Error "Fehler beim Laden/Speichern des Validierungsreports für Rechnung ID $invoice_id : $(Format-ApiError $_)"
            $success = $false
        }
    }

    # Anhänge laden. Die Liste enthält laut API auch die Originalrechnung als
    # einzige XML-Datei; diese liegt bereits im XML-Verzeichnis und wird übersprungen.
    if ($load_attachments) {
        $attachment_ids = @($invoice.attachments | Where-Object { $null -ne $_ })
        $used_names = @{}
        foreach ($attachment_id in $attachment_ids) {
            $attachment_id = [string]$attachment_id
            try {
                if (-not [guid]::TryParse($attachment_id, [ref]$guid)) {
                    throw "Ungültige Attachment-ID '$attachment_id'"
                }
                Write-Debug "Lade Attachment ID '$attachment_id'..."
                $attachment = Invoke-ApiJson -Path "/api/attachment/$attachment_id/document"

                $is_xml = ("$($attachment.fileName)" -match '\.xml$') -or ("$($attachment.mimeType)" -match 'xml')
                if ($is_xml) {
                    Write-Debug "Attachment '$($attachment.fileName)' ist die Rechnungs-XML und wird übersprungen."
                    continue
                }

                $name = Get-SafeFileName -FileName $attachment.fileName -Fallback "$attachment_id.bin"
                if ($used_names.ContainsKey($name.ToLowerInvariant())) {
                    $name = "$attachment_id-$name"
                }
                $used_names[$name.ToLowerInvariant()] = $true

                $file_attachment = Join-Path $files_attachment "$invoice_id-attachment-$name"
                $content = "$($attachment.content)"
                if ([string]::IsNullOrEmpty($content)) {
                    throw "Attachment hat keinen Inhalt."
                }
                Write-Info "Speichere '$file_attachment'"
                Save-Bytes -Path $file_attachment -Bytes ([Convert]::FromBase64String($content))
                [void]$entry.Attachments.Add([ordered]@{
                    AttachmentId = $attachment_id
                    FileName     = "$($attachment.fileName)"
                    MimeType     = "$($attachment.mimeType)"
                    File         = $file_attachment
                })
            } catch {
                Write-Error "Fehler beim Laden/Speichern des Attachments $attachment_id für Rechnung ID $invoice_id : $(Format-ApiError $_)"
                $success = $false
            }
        }
    }

    # Rechnung als heruntergeladen markieren
    if ($success -and $NoMark) {
        Write-Warning "Testmodus (-NoMark): Rechnung ID $invoice_id wird nicht als heruntergeladen markiert."
    } elseif ($success) {
        try {
            Write-Info "Markiere Rechnung ID $invoice_id als 'heruntergeladen'..."
            [void](Invoke-Api -Method Patch -Path "/api/invoice/$invoice_id/downloaded")
            $entry.Marked = $true
        } catch {
            Write-Error "Fehler beim Markieren als 'heruntergeladen'. Rechnung ID $invoice_id : $(Format-ApiError $_)"
            $success = $false
        }
    } else {
        Write-Warning "Aufgrund vorheriger Fehler wird die Rechnung ID $invoice_id nicht als heruntergeladen markiert."
    }

    $entry.Success = $success
    if (-not $success) {
        $exit_code = 2
    }
}

# Manifest schreiben (auch ohne Workflow-Skript, als Nachweis des Laufs)
$manifest_file = $null
if ($manifest_invoices.Count -gt 0) {
    try {
        $manifest_file = Save-Manifest -Directory $files_manifest -Started $run_started -ExitCode $exit_code -NoMark:$NoMark -Invoices $manifest_invoices
        Write-Info "Manifest gespeichert: '$manifest_file'"
    } catch {
        Write-Error "Fehler beim Speichern des Manifests: $($_.Exception.Message)"
    }
}

# Workflow-Skript starten, wenn mindestens eine Rechnung vollständig gespeichert wurde
$success_count = @($manifest_invoices | Where-Object { $_.Success }).Count
if ($use_workflow) {
    if ($success_count -eq 0) {
        Write-Info "Keine neuen Rechnungen gespeichert, Workflow-Skript wird nicht gestartet."
    } elseif ($NoMark) {
        Write-Warning "Testmodus (-NoMark): Workflow-Skript wird nicht gestartet (Rechnungen würden beim nächsten Lauf erneut verarbeitet)."
    } elseif ($null -eq $manifest_file) {
        Write-Error "Workflow-Skript wird nicht gestartet, da kein Manifest gespeichert werden konnte."
        $exit_code = 3
    } else {
        if (-not (Invoke-Workflow -Script $workflowscript -ExitCode $exit_code -ManifestPath $manifest_file -TimeoutSec $workflow_timeout)) {
            $exit_code = 3
        }
    }
}

Write-Info "Fertig (Exit-Code $exit_code)."
Stop-Transcript | Out-Null
exit $exit_code

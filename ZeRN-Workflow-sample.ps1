###############################################################################
# ZeRN-Downloader - Beispiel für ein Workflow-Skript
#
# Wird vom ZeRN-Downloader nach jedem Lauf gestartet, in dem mindestens eine
# Rechnung vollständig gespeichert wurde (Konfiguration: $workflowscript).
#
# Aufruf: powershell.exe -File <Skript> -ExitCode <n> -ManifestPath <Pfad>
#   -ExitCode      Exit-Code des Downloads (0 = OK, 2 = einzelne Rechnungen fehlerhaft)
#   -ManifestPath  JSON-Datei mit allen Rechnungen des Laufs
#
# Wichtig:
# - Nur Rechnungen mit Success = true verarbeiten. Fehlerhafte Rechnungen
#   bleiben im ZeRN auf "neu" und kommen beim nächsten Lauf erneut.
# - Exit-Code 0 = Erfolg. Alles andere führt beim Downloader zu Exit-Code 3.
# - Ausgaben (Write-Output, Fehler) landen im Protokoll des Downloaders.
# - Das Skript läuft in einem eigenen Prozess und kennt keine Variablen
#   (z.B. Passwort) des Downloaders.
###############################################################################

param (
    [int]$ExitCode = 0,
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath
)

$ErrorActionPreference = "Stop"

try {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    Write-Output "Manifest: $ManifestPath (Download-Exit-Code $ExitCode)"
    Write-Output "$($manifest.SuccessCount) von $($manifest.InvoiceCount) Rechnung(en) erfolgreich"

    foreach ($invoice in @($manifest.Invoices | Where-Object { $_.Success })) {
        Write-Output ("{0} | {1} | {2} | TypeCode {3} | {4}" -f `
            $invoice.InvoiceId, $invoice.SenderName, $invoice.SenderInvoiceNumber, $invoice.TypeCode, $invoice.XmlFile)

        foreach ($attachment in @($invoice.Attachments)) {
            Write-Output "    Anhang: $($attachment.File)"
        }

        # Hier die eigene Verarbeitung einfügen, z.B.:
        # Copy-Item -LiteralPath $invoice.XmlFile -Destination "\\server\import\" -ErrorAction Stop
    }

    exit 0
} catch {
    # Landet als Fehler im Protokoll des Downloaders
    [Console]::Error.WriteLine("Workflow fehlgeschlagen: $($_.Exception.Message)")
    exit 1
}

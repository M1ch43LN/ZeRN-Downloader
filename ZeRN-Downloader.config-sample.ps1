###############################################################################
# ZeRN-Downloader - Konfiguration
#
# Diese Datei nach "ZeRN-Downloader.config.ps1" kopieren und anpassen.
#
# Wichtig: Als UTF-8 MIT BOM speichern (z.B. Notepad: "UTF-8 mit BOM"), sonst
# liest Windows PowerShell 5.1 Umlaute falsch (relevant v.a. für das Passwort).
###############################################################################

#------------------------------------------------------------------------------
# Zugangsdaten
#------------------------------------------------------------------------------

# Benutzername für den Zugriff auf die API
$api_username = "erechnung@domain.de"

# Passwort für den Zugriff auf die API
# Einfache Anführungszeichen verwenden, falls das Passwort $ oder ` enthält
$api_password = 'VerYS3cretP@ssw0rd'

# Optional: Timeout je API-Aufruf in Sekunden (Standard: 120)
#$api_timeout = 120

#------------------------------------------------------------------------------
# Verzeichnisse
# Nicht vorhandene Verzeichnisse werden beim Start angelegt.
#------------------------------------------------------------------------------

# Rechnungen (XML), deren Syntax nicht erkannt wurde
$files_xml = "$PSScriptRoot\xml"

# Rechnungen (XML) in CII-Syntax
$files_xml_cii = "$PSScriptRoot\xml_cii"

# Rechnungen (XML) in UBL-Syntax (Invoice und CreditNote)
$files_xml_ubl = "$PSScriptRoot\xml_ubl"

# Validierungsreports (KoSIT) der Rechnungen
# Leerer String deaktiviert das Herunterladen der Validierungsreports
#$files_validation = "$PSScriptRoot\validation"
$files_validation = ""

# Anhänge der Rechnungen (PDF etc.; die Rechnungs-XML selbst wird hier nicht abgelegt)
# Leerer String deaktiviert das Herunterladen der Anhänge
#$files_attachment = "$PSScriptRoot\attachment"
$files_attachment = ""

# Protokolldateien (eine Datei je Tag)
$files_log = "$PSScriptRoot\log"

# Optional: Manifeste der Läufe (JSON, eine Datei je Lauf mit Rechnungen)
# Standard: Unterverzeichnis "manifest" im Protokollverzeichnis
#$files_manifest = "$PSScriptRoot\log\manifest"

#------------------------------------------------------------------------------
# Protokollierung
#------------------------------------------------------------------------------

# Detailgrad der Protokollierung. Mögliche Werte:
# - $log_debug   (sehr ausführlich, nur zur Fehlersuche)
# - $log_info    (Standard)
# - $log_warning
# - $log_error
$log_level = $log_info

#------------------------------------------------------------------------------
# Workflow-Skript (optional)
#------------------------------------------------------------------------------

# PowerShell-Skript, das nach jedem Lauf mit mindestens einer vollständig
# gespeicherten Rechnung gestartet wird (eigener Prozess, Parameter -ExitCode
# und -ManifestPath). Nicht bei 0 Rechnungen, Abbruch oder -NoMark.
# Vorlage: ZeRN-Workflow-sample.ps1. Leerer String = kein Workflow-Skript
#$workflowscript = "$PSScriptRoot\ZeRN-Workflow.ps1"
$workflowscript = ""

# Optional: maximale Laufzeit des Workflow-Skripts in Sekunden
# (0 = unbegrenzt, Standard: 3600)
#$workflow_timeout = 3600

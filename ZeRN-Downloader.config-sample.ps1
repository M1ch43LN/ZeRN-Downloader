# Benutzername für den Zugriff auf die API
$api_username = "erechnung@domain.de"

# Passwort für den Zugriff auf die API
$api_password = "VerYS3cretP@ssw0rd"

# Verzeichnis, in dem die Rechnungen im XML-Format gespeichert werden sollen, deren Syntax nicht erkannt wurde
$files_xml = "$PSScriptRoot\xml"

# Verzeichnis, in dem die Rechnungen im XML-Format mit CII-Syntax gespeichert werden sollen
$files_xml_cii = "$PSScriptRoot\xml_cii"

# Verzeichnis, in dem die Rechnungen im XML-Format mit UBL-Syntax gespeichert werden sollen
$files_xml_ubl = "$PSScriptRoot\xml_ubl"

# Verzeichnis, in dem die Validierungsreports der Rechnungen gespeichert werden sollen.
# Leerer String deaktiviert das Herunterladen der Validierungsreports
#$files_validation = "$PSScriptRoot\validation"
$files_validation = ""

# Verzeichnis, in dem die Anhänge der Rechnungen gespeichert werden sollen.
# Leerer String deaktiviert das Herunterladen der Anhänge
#$files_attachment = "$PSScriptRoot\attachment"
$files_attachment = ""

# Pfad, in dem die Protokolldateien gespeichern werden sollen
$files_log = "$PSScriptRoot\log"

# Detailgrad der Protokollierung. Mögliche Werte:
# - $log_debug
# - $log_info (Standard)
# - $log_warning
# - $log_error
$log_level = $log_info

# Optional: PowerShell-Skript, das nach jedem Lauf mit neu gespeicherten Rechnungen
# gestartet wird (eigener Prozess, Parameter -ExitCode und -ManifestPath).
# Vorlage: ZeRN-Workflow-sample.ps1. Leerer String = kein Workflow-Skript
#$workflowscript = "$PSScriptRoot\ZeRN-Workflow.ps1"
$workflowscript = ""

# Optional: maximale Laufzeit des Workflow-Skripts in Sekunden (0 = unbegrenzt, Standard: 3600)
#$workflow_timeout = 3600

# Optional: Verzeichnis für die Manifeste der Läufe (Standard: Unterverzeichnis "manifest" im Log-Verzeichnis)
#$files_manifest = "$PSScriptRoot\log\manifest"

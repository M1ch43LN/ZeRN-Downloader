# Benutzername für den Zugriff auf die API
$api_username = "erechnung@domain.de"

# Passwort für den Zugriff auf die API
$api_password = "VerYS3cretP@ssw0rd"

# Verzeichnis in dem die Rechnungen im XML-Format gespeichert werden sollen
$files_xml = "$PSScriptRoot\xml"

# Verzeichnis in dem die Validierungsreports der Rechnungen gespeichert werden sollen.
# Leerer String deaktiviert das Herunterladen der Validierungsreports
#$files_validation = "$PSScriptRoot\validation"
$files_validation = ""

# Pfad, in dem die Protokolldateien gespeichern werden sollen
$files_log = "$PSScriptRoot\log"

# Detailgrad der Protokollieren. Mögliche Werte:
# - $log_debug
# - $log_info (Standard)
# - $log_warning
# - $log_error
$log_level = $log_info
# ZeRN-Downloader
Powershell-Skript zum automatisierten Herunterladen von eRechnungen (XRechnung) aus dem ZeRN (Zentraler eRechnungseingang Niedersachsen) per REST-API.

Das Skript ist darauf ausgelegt, auf einem Windows-Server per Aufgabenplaner regelmäßig (z.B. einmal pro Stunde) ausgeführt zu werden. Die eRechnungsdateien werden aus dem ZeRN-Portal heruntergeladen und anschließend als "heruntergeladen" markiert.

## Voraussetzungen
Um mit dem Skript eRechnungen aus dem ZeRN-Portal abrufen zu können, muss die API-Schnittstelle für das gewünschte Benutzerkonto vom Land freigeschaltet worden sein. 

Informationen zur Schnittstelle und deren Freischaltung gibt es [hier](https://rechnung.niedersachsen.de/startseite/informationen-fuer-rechnungsempfaenger/schnittstelle-zum-abruf-von-rechnungen-210483.html).

## Installation und Konfiguration
Alle Dateien müssen in ein Arbeitsverzeichnis kopiert werden, z.B. `C:\ZeRN`.

Im Arbeitsverzeichnis muss eine Konfigurationsdatei `ZeRN-Downloader.config.ps1` angelegt werden. Als Vorlage durch Umbenennen kann hierfür die Datei `ZeRN-Downloader.config-sample.ps1` aus dem Repository verwendet werden.

Folgende Konfigurationen müssen festgelegt werden:

```powershell
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

# Detailgrad der Protokolle. Mögliche Werte:
# - $log_debug
# - $log_info (Standard)
# - $log_warning
# - $log_error
$log_level = $log_info
```

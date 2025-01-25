# Funktionen laden
. "$PSScriptRoot\ZeRN-Downloader.functions.ps1"
# Konfiguration laden
. "$PSScriptRoot\ZeRN-Downloader.config.ps1"

# Protokoll starten
$log_date = Get-Date -Format "yyyy-MM-dd"
Start-Transcript -Path "$files_log\$log_date.log" -Append

# API-URLs definieren
$api_baseurl = "https://api.erechnung.niedersachsen.de"
$api_endpoint_accesstoken = "/api/accesstoken/create"
$api_endpoint_invoice_new = "/api/invoice/new"
$api_endpoint_invoice_xml = "/api/invoice/{invoiceId}/xml"
$api_endpoint_invoice_validation = "/api/invoice/{invoiceId}/validationreport"
$api_endpoint_invoice_downloaded = "/api/invoice/{invoiceId}/downloaded"

# API-Headers setzen
$api_headers = @{}
$api_headers.Add("accept","application/json")
$api_headers.Add("Content-Type","application/json")

# Body für Authorisierung
$body = "{ ""userName"": ""$api_username"", ""password"": ""$api_password"" }"

# Anmeldung an API, Access Token holen
try {    
    $url = -join($api_baseurl,$api_endpoint_accesstoken)
    Write-Debug "API-URL: $url"
    $response_auth = Invoke-RestMethod -Method Post -Uri $url -Headers $api_headers -ContentType "application/json" -Body $body
    $api_accesstoken = $response_auth.accessToken    
    $api_headers.add("Authorization", "Bearer $api_accesstoken")
    Write-Info "Anmeldung an API erfolgreich."
} catch {
    Write-Error "Fehler bei der Anmeldung..."
    Write-Error $_ "error"
    exit
}

try {
    $url = -join($api_baseurl,$api_endpoint_invoice_new)
    Write-Debug "API-URL: $url"

    # Liste neuer Rechnungen holen
    $response_invoices = Invoke-RestMethod -Method Get -Uri $url -Headers $api_headers -ContentType "application/json"

    Write-Info "$($response_invoices.Count) neue Rechung(en) vorhanden..."

    foreach ($invoice in $response_invoices) {
        $invoice_id = $invoice.id
        $success = $true
                
        $url = -join($api_baseurl,$api_endpoint_invoice_xml)
        $url = $url.Replace("{invoiceId}", $invoice_id)
        Write-Debug "API-URL: $url"       

        # XML-Datei der Rechnung herunterladen
        try {
            Write-Info "Lade XML-Rechnung ID '$invoice_id'..."
            Write-Debug "Empfangen: $($invoice.received)"
            Write-Debug "Absender: $($invoice.sender.name)"
            Write-Debug "Rechnungsnummer: $($invoice.senderInvoiceNumber)"
            Write-Debug "Schema: $($invoice.scheme)"
            Write-Debug "Status: $($invoice.status)"            
            $response_xml = Invoke-RestMethod -Method Get -Uri $url -Headers $api_headers -ContentType "application/json" 

            # XML-Datei speichern
            try {
                $file_xml = "$files_xml\$invoice_id.xml"
                Write-Info "Speichere '$file_xml'"
                $response_xml.InnerXml | Out-File -Encoding utf8 -FilePath $file_xml -Force

                if ($files_validation -ne "") {
                    # Validationsreport laden
                    $url = -join($api_baseurl,$api_endpoint_invoice_validation)
                    $url = $url.Replace("{invoiceId}", $invoice_id)
                    Write-Debug "API-URL: $url"
                    try {
                        Write-Info "Lade Validierungsreport ID '$invoice_id'..."                    
                        $response_validation = Invoke-RestMethod -Method Get -Uri $url -Headers $api_headers -ContentType "application/json" 
                    } catch {
                        Write-Error "Fehler beim Laden des Validierungsreports für Rechnung ID $invoice_id"
                        Write-Error $_
                        $success = $false
                    }

                    # Validationreport speichern
                    try {
                        $file_validation = "$files_validation\$invoice_id.xml"
                        Write-Info "Speichere '$file_validation'"
                        $response_validation.InnerXml | Out-File -Encoding utf8 -FilePath $file_validation -Force
                    } catch {
                        Write-Error "Fehler beim Schreiben des Validierungsreports $file_validation für Rechnung ID $invoice_id"
                        Write-Error $_
                        $success = $false
                    }
                }
            } catch {
                Write-Error "Fehler beim Schreiben der XML-Rechnung $file_xml für Rechnung ID $invoice_id"
                Write-Error $_
                $success = $false
            }

            if ($success -eq $true) {
                # Rechnung als heruntergeladen markieren
                $url = -join($api_baseurl,$api_endpoint_invoice_downloaded)
                $url = $url.Replace("{invoiceId}", $invoice_id)
                Write-Debug "API-URL: $url"
                Write-Info "Markiere Rechnung ID $invoice_id als 'heruntergeladen'..."
                try {
                    $response_downloaded = Invoke-RestMethod -Method Patch -Uri $url -Headers $api_headers -ContentType "application/json" 
                } catch {
                    Write-Error "Fehler beim Markieren als 'heruntergeladen'. Rechnung ID $invoice_id"
                    Write-Error $_
                    $success = $false
                }  
            } else {
                Write-Warning "Aufgrund vorheriger Fehler oder Warnungen wird die Rechnung nicht als heruntergeladen markiert."
            }
        } catch {
            Write-Error "Fehler beim Laden der XML-Datei für Rechnung ID $invoice_id"
            Write-Error $_
        }        
    }

} catch {
    Write-Error "Fehler beim Laden der Rechnungsliste..."
    Write-Error $_
    exit
}

Stop-Transcript

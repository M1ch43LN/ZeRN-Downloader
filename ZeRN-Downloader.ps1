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
$api_endpoint_attachment = "/api/attachment/{attachmentId}"

# API-Headers setzen
$api_headers = @{}
$api_headers.Add("accept","application/json")

$api_headers_attachment = @{}
$api_headers_attachment.Add("accept", "application/octet-stream")

# Body für Authorisierung
$body = "{ ""userName"": ""$api_username"", ""password"": ""$api_password"" }"

# User Agent
$useragent = "ZeRN-Downloader/1.0 (https://github.com/M1ch43LN/ZeRN-Downloader)"

# Anmeldung an API, Access Token holen
try {    
    $url = -join($api_baseurl,$api_endpoint_accesstoken)
    Write-Debug "API-URL: $url"
    $response_auth = Invoke-RestMethod -Method Post -Uri $url -Headers $api_headers -ContentType "application/json" -Body $body -UserAgent $useragent
    $api_accesstoken = $response_auth.accessToken    
    $api_headers.add("Authorization", "Bearer $api_accesstoken")
    $api_headers_attachment.add("Authorization", "Bearer $api_accesstoken")
    Write-Info "Anmeldung an API erfolgreich."
    Write-Debug "Access Token: $api_accesstoken"
} catch {
    Write-Error "Fehler bei der Anmeldung..."
    Write-Error $_ "error"
    exit
}

try {
    $url = -join($api_baseurl,$api_endpoint_invoice_new)
    Write-Debug "API-URL: $url"

    # Liste neuer Rechnungen holen
    $response_invoices = Invoke-RestMethod -Method Get -Uri $url -Headers $api_headers -ContentType "application/json" -UserAgent $useragent

    Write-Info "$($response_invoices.Count) neue Rechung(en) vorhanden..."

    foreach ($invoice in $response_invoices) {
        $invoice_id = $invoice.id
        $success = $true
                
        $url = -join($api_baseurl,$api_endpoint_invoice_xml)
        $url = $url.Replace("{invoiceId}", $invoice_id)        

        # XML-Datei der Rechnung herunterladen
        try {
            Write-Info  "Lade XML-Rechnung ID '$invoice_id'..."
            Write-Debug "API-URL: $url"
            Write-Debug "Empfangen: $($invoice.received)"
            Write-Debug "Absender: $($invoice.sender.name)"
            Write-Debug "Rechnungsnummer: $($invoice.senderInvoiceNumber)"
            Write-Debug "Schema: $($invoice.scheme)"
            Write-Debug "Status: $($invoice.status)"            
            $response_xml = Invoke-RestMethod -Method Get -Uri $url -Headers $api_headers -ContentType "application/json" -UserAgent $useragent

            # XML-Datei speichern
            try {
                $file_xml = "$files_xml\$invoice_id.xml"
                Write-Info "Speichere '$file_xml'"
                $response_xml.InnerXml | Out-File -Encoding utf8 -FilePath $file_xml -Force

                # Validationsreport laden
                if ($files_validation -ne "") {                    
                    $url = -join($api_baseurl,$api_endpoint_invoice_validation)
                    $url = $url.Replace("{invoiceId}", $invoice_id)
                    Write-Debug "API-URL: $url"
                    try {
                        Write-Info "Lade Validierungsreport ID '$invoice_id'..."                    
                        $response_validation = Invoke-RestMethod -Method Get -Uri $url -Headers $api_headers -ContentType "application/json" -UserAgent $useragent
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

                # Attachments laden
                if ($files_attachment -ne "") {
                    Write-Info "Anhänge/Attachments werden heruntergeladen..."
                    foreach ($attachment_id in $response_invoices.attachments) {                                            
                        $url = -join($api_baseurl,$api_endpoint_attachment)
                        $url = $url.Replace("{attachmentId}", $attachment_id)                        
                        try {
                            Write-Info "Lade Attachment ID '$attachment_id'..."                    
                            Write-Debug "Attachment-ID: $attachment_id"
                            Write-Debug "API-URL: $url"
                            $response_attachment = Invoke-WebRequest -Method Get -Uri $url -Headers $api_headers_attachment -ContentType "application/octet-stream" -UserAgent $useragent                            
                            $filename_attachment = $response_attachment.Headers.'Content-Disposition'.Split("=")[1].Replace("`"","").Split(";")[0]
                            $file_attachment = "$files_attachment\$invoice_id-attachment-$filename_attachment"
                            Write-Debug "Dateiname: $file_attachment"
                            try {
                                $file = [System.IO.FileStream]::new($file_attachment, [System.IO.FileMode]::Create)
                                $file.write($response_attachment.Content, 0, $response_attachment.RawContentLength)
                                $file.close()
                            } catch {
                                Write-Error "Fehler beim Speichern des Attachments $attachment_id für Rechnung ID $invoice_id"
                                Write-Error $_
                                $success = $false
                            }
                        } catch {
                            Write-Error "Fehler beim Laden des Attachments $attachment_id für Rechnung ID $invoice_id"
                            Write-Error $_
                            $success = $false
                        }
                    }
                }
            } catch {
                Write-Error "Fehler beim Schreiben der XML-Rechnung $file_xml für Rechnung ID $invoice_id"
                Write-Error $_
                $success = $false
            }

            # Rechnung als heruntergeladen markieren
            if ($success -eq $true) {                
                $url = -join($api_baseurl,$api_endpoint_invoice_downloaded)
                $url = $url.Replace("{invoiceId}", $invoice_id)
                Write-Info "Markiere Rechnung ID $invoice_id als 'heruntergeladen'..."
                Write-Debug "API-URL: $url"                
                try {
                    Invoke-RestMethod -Method Patch -Uri $url -Headers $api_headers -ContentType "application/json" -UserAgent $useragent
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

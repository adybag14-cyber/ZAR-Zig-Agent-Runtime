param(
    [int] $Port,
    [string] $ReadyPath,
    [string] $StatusPath,
    [string] $RequestLogPath
)

$ErrorActionPreference = 'Stop'

function Get-HeaderValue {
    param(
        [string] $HeaderText,
        [string] $Name
    )

    $match = [System.Text.RegularExpressions.Regex]::Match(
        $HeaderText,
        "(?im)^" + [System.Text.RegularExpressions.Regex]::Escape($Name) + ":\s*(.+)$"
    )
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return $null
}

$utf8 = [System.Text.Encoding]::UTF8
$ascii = [System.Text.Encoding]::ASCII
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
$request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    'CN=zar-fs55-https',
    $rsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)
$request.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $false)
)
$request.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor
        [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment,
        $false
    )
)
$eku = [System.Security.Cryptography.OidCollection]::new()
$null = $eku.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'))
$request.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($eku, $false)
)
$request.CertificateExtensions.Add(
    [System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($request.PublicKey, $false)
)
$ephemeralCert = $request.CreateSelfSigned(
    [System.DateTimeOffset]::UtcNow.AddDays(-1),
    [System.DateTimeOffset]::UtcNow.AddDays(14)
)
$pfxPassword = 'zar-fs55-https'
$pfxBytes = $ephemeralCert.Export(
    [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx,
    $pfxPassword
)
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $pfxBytes,
    $pfxPassword,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)

try {
    $listener.Start()
    Set-Content -Path $ReadyPath -Value 'ready' -Encoding Ascii

    $client = $listener.AcceptTcpClient()
    try {
        Set-Content -Path $StatusPath -Value 'accepted' -Encoding Ascii
        $client.ReceiveTimeout = 10000
        $client.SendTimeout = 10000
        $stream = $client.GetStream()
        $ssl = [System.Net.Security.SslStream]::new($stream, $false)
        try {
            $ssl.AuthenticateAsServer(
                $cert,
                $false,
                [System.Security.Authentication.SslProtocols]::Tls12 -bor [System.Security.Authentication.SslProtocols]::Tls13,
                $false
            )
            Set-Content -Path $StatusPath -Value 'tls-ok' -Encoding Ascii

            $requestBuffer = [System.IO.MemoryStream]::new()
            $readBuffer = New-Object byte[] 4096
            $contentLength = $null
            $headerEnd = -1

            while ($true) {
                $read = $ssl.Read($readBuffer, 0, $readBuffer.Length)
                if ($read -le 0) {
                    throw 'peer closed before request completed'
                }

                $requestBuffer.Write($readBuffer, 0, $read)
                $requestBytes = $requestBuffer.ToArray()
                $requestText = $ascii.GetString($requestBytes)

                if ($headerEnd -lt 0) {
                    $headerEnd = $requestText.IndexOf("`r`n`r`n", [System.StringComparison]::Ordinal)
                    if ($headerEnd -ge 0) {
                        $headerText = $requestText.Substring(0, $headerEnd)
                        $contentLengthText = Get-HeaderValue -HeaderText $headerText -Name 'Content-Length'
                        if ($null -eq $contentLengthText) {
                            throw 'missing Content-Length header'
                        }
                        $contentLength = [int]$contentLengthText
                    }
                }

                if ($headerEnd -ge 0 -and $requestBytes.Length -ge ($headerEnd + 4 + $contentLength)) {
                    break
                }
            }

            $finalRequestText = $ascii.GetString($requestBuffer.ToArray())
            Set-Content -Path $RequestLogPath -Value $finalRequestText -Encoding Ascii

            $headerText = $finalRequestText.Substring(0, $headerEnd)
            $headerLines = $headerText -split "`r?`n"
            $requestLine = if ($headerLines.Length -gt 0) { $headerLines[0].Trim() } else { '' }
            if ($requestLine -ne 'POST /fs55/live-https HTTP/1.1') {
                throw 'unexpected request line'
            }
            $hostHeader = Get-HeaderValue -HeaderText $headerText -Name 'Host'
            if ($hostHeader -ne '10.0.2.2:8443') {
                throw 'unexpected host header'
            }
            $contentType = Get-HeaderValue -HeaderText $headerText -Name 'Content-Type'
            if ($contentType -ne 'application/json') {
                throw 'missing content-type header'
            }

            $body = $finalRequestText.Substring($headerEnd + 4)
            if ($body -ne '{"probe":"live-https"}') {
                throw "unexpected request body: $body"
            }
            Set-Content -Path $StatusPath -Value 'request-ok' -Encoding Ascii

            $responseBody = '{"ok":true,"transport":"https"}'
            $responseText = "HTTP/1.1 200 OK`r`nContent-Length: $($responseBody.Length)`r`nConnection: close`r`nContent-Type: application/json`r`n`r`n$responseBody"
            $responseBytes = $utf8.GetBytes($responseText)
            $ssl.Write($responseBytes, 0, $responseBytes.Length)
            $ssl.Flush()
            Set-Content -Path $StatusPath -Value 'ok' -Encoding Ascii
        }
        finally {
            $ssl.Dispose()
        }
    }
    finally {
        $client.Dispose()
    }
}
catch {
    Set-Content -Path $StatusPath -Value $_.ToString() -Encoding UTF8
    throw
}
finally {
    $listener.Stop()
    $cert.Dispose()
    $ephemeralCert.Dispose()
    $rsa.Dispose()
}



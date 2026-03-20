# SPDX-License-Identifier: GPL-2.0-only
param(
    [int] $ListenPort,
    [int] $ReplyPort,
    [int] $TimeoutSeconds = 30,
    [int] $ReplyDelayMs = 0,
    [string] $RemoteMac = '02:5A:52:10:00:E1'
)

$ErrorActionPreference = 'Stop'

function Convert-MacStringToBytes {
    param([string] $Value)

    $parts = $Value -split '[:-]'
    if ($parts.Length -ne 6) {
        throw "Invalid MAC address: $Value"
    }

    $bytes = New-Object byte[] 6
    for ($i = 0; $i -lt 6; $i += 1) {
        $bytes[$i] = [Convert]::ToByte($parts[$i], 16)
    }
    return $bytes
}

$remoteMacBytes = Convert-MacStringToBytes -Value $RemoteMac
$udp = [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $ListenPort))
$udp.Client.ReceiveTimeout = $TimeoutSeconds * 1000
$peer = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)

try {
    $frame = $udp.Receive([ref] $peer)
    Write-Output "E1000_ECHO_FROM=$($peer.Address):$($peer.Port)"
    Write-Output "E1000_ECHO_FRAME_LEN=$($frame.Length)"

    if ($frame.Length -lt 60) {
        throw "Frame too short: $($frame.Length)"
    }

    $reply = New-Object byte[] $frame.Length
    [Array]::Copy($frame, $reply, $frame.Length)

    for ($i = 0; $i -lt 6; $i += 1) {
        $reply[$i] = $frame[6 + $i]
        $reply[6 + $i] = $remoteMacBytes[$i]
    }

    if ($ReplyDelayMs -gt 0) {
        Start-Sleep -Milliseconds $ReplyDelayMs
    }
    $replyEndpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $ReplyPort)
    $bytesSent = $udp.Send($reply, $reply.Length, $replyEndpoint)
    Write-Output "E1000_ECHO_SENT=$bytesSent"
    Write-Output "E1000_ECHO_REPLY_PORT=$ReplyPort"
    Write-Output "E1000_ECHO_REPLY_DELAY_MS=$ReplyDelayMs"
    Write-Output 'E1000_ECHO_STATUS=ok'
}
finally {
    $udp.Close()
}

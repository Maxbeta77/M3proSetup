# M3PRO public setup launcher: no GitHub token required.
[CmdletBinding()]
param([switch]$DownloadOnly, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$uri = 'https://raw.githubusercontent.com/Maxbeta77/M3proSetup/setup-2026-10-07-2/INSTALLA-M3-GUI.ps1'
$expected = '9fb0c4917906600ce1831fe71a87dcbef3626a638d5071a05b4fe1763ddc9669'
$destination = Join-Path $env:TEMP ('M3PRO-Setup-' + [guid]::NewGuid().ToString('N') + '.ps1')
Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $destination -TimeoutSec 120
if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) {
    throw 'Download del setup non valido: SHA256 diverso da quello pubblicato.'
}
if ($DownloadOnly) { Write-Output $destination; return }
$flags = if ($CheckOnly) {' -CheckOnly'} else {''}
Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "' + $destination + '"' + $flags)
Write-Host 'Setup grafico M3PRO avviato. Conferma Windows se viene richiesta autorizzazione amministratore.'

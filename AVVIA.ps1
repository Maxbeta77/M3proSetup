# M3PRO public setup launcher: no GitHub token required.
[CmdletBinding()]
param([switch]$DownloadOnly, [switch]$CheckOnly, [switch]$ResumeIncomplete)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$uri = 'https://raw.githubusercontent.com/Maxbeta77/M3proSetup/setup-2026-10-07-3/INSTALLA-M3-GUI.ps1'
$expected = 'ea4c40d4b62fb6e5a87141141c78e973a96e0bd967e3701dc3c9d711f5e8bf36'
$destination = Join-Path $env:TEMP ('M3PRO-Setup-' + [guid]::NewGuid().ToString('N') + '.ps1')
Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $destination -TimeoutSec 120
if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) {
    throw 'Download del setup non valido: SHA256 diverso da quello pubblicato.'
}
if ($DownloadOnly) { Write-Output $destination; return }
$flags = if ($CheckOnly) {' -CheckOnly'} else {''}
if ($ResumeIncomplete) { $flags += ' -ResumeIncomplete' }
Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Normal -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "' + $destination + '"' + $flags)
Write-Host 'Avvio richiesto per il setup M3PRO. Conferma Windows se viene richiesta autorizzazione amministratore.'

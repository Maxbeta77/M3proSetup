# M3PRO public setup launcher: no GitHub token required.
[CmdletBinding()]
param([switch]$DownloadOnly, [switch]$CheckOnly, [switch]$ResumeIncomplete)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$uri = 'https://raw.githubusercontent.com/Maxbeta77/M3proSetup/setup-2026-10-07-4/INSTALLA-M3-GUI.ps1'
$expected = '602ce9ac0d9fb5fd56bfa208c52831b1641ec8b56c2e2e6cba5959b3fc4a46e6'
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

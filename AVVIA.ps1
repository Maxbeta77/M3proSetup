# M3PRO public setup launcher: no GitHub token required.
[CmdletBinding()]
param([switch]$DownloadOnly, [switch]$CheckOnly, [switch]$ResumeIncomplete)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$uri = 'https://raw.githubusercontent.com/Maxbeta77/M3proSetup/setup-2026-10-07-5/INSTALLA-M3-GUI.ps1'
$expected = 'ee2bada4d138ec95aa6ea5af7e6cb6729256a50c29e25d691013bd2daa3f6f0b'
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

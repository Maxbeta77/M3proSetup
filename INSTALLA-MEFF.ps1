#requires -Version 5.1
<#
M3PRO - Installazione nuova macchina Windows x64.
Scarica SEMPRE la release stable approvata dal portale (non il ramo Git).
Uso: powershell -ExecutionPolicy Bypass -File .\INSTALLA-MEFF.ps1
Verifica senza installare: aggiungere -CheckOnly
Una cartella Git appena clonata viene archiviata integralmente prima del setup.
Un M3 gia' configurato deve usare Update: questo installer non lo sovrascrive.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$ChecklistOnly,
    [string]$StatusFile = '',
    [string]$ConfigFile = '',
    [switch]$SkipExternalTools
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$InstallRoot = 'C:\MEFF'
$Feed = 'https://pc-network-scan.emergent.host/api/update-feed'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$BootstrapSource = [IO.File]::ReadAllText($PSCommandPath)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Work = Join-Path $env:TEMP ('M3-Setup-' + [guid]::NewGuid().ToString('N'))

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, $Utf8)
}
function Run-Checked([string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue' # Windows PowerShell: stderr non implica exit code != 0.
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Comando fallito: $Exe (codice $LASTEXITCODE)." }
}
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
function Install-Winget([string]$Id) {
    Write-Host "Installazione prerequisito: $Id"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Per installare $Id serve App Installer (winget) di Microsoft. Installarlo e riprovare."
    }
    Run-Checked 'winget' @('install','--id',$Id,'--exact','--source','winget','--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
    Refresh-Path
}
function Find-Python312 {
    $ErrorActionPreference = 'Continue'
    $paths = @("$env:LOCALAPPDATA\Programs\Python\Python312\python.exe", "$env:ProgramFiles\Python312\python.exe", 'C:\Python312\python.exe')
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $probe = & py -3.12 -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0) { $paths = @($probe) + $paths }
    }
    foreach ($candidate in $paths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            & $candidate -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3,12) and sys.maxsize > 2**32 else 1)' 2>$null
            if ($LASTEXITCODE -eq 0) { return $candidate }
        }
    }
    return $null
}
function Show-InstallationChecklist {
    $py = Find-Python312
    $rows = @(
        [pscustomobject]@{Componente='Windows x64'; Stato=$(if([Environment]::Is64BitOperatingSystem){'OK'}else{'NON COMPATIBILE'}); Azione='Windows 10/11 x64'},
        [pscustomobject]@{Componente='Python 3.12 x64'; Stato=$(if($py){'PRESENTE'}else{'MANCANTE'}); Azione='Installazione automatica tramite winget'},
        [pscustomobject]@{Componente='Node.js / npm'; Stato=$(if(Get-Command npm.cmd -ErrorAction SilentlyContinue){'PRESENTE'}else{'MANCANTE'}); Azione='Installazione automatica tramite winget'},
        [pscustomobject]@{Componente='winget'; Stato=$(if(Get-Command winget -ErrorAction SilentlyContinue){'PRESENTE'}else{'MANCANTE'}); Azione='Microsoft App Installer, richiesto per prerequisiti mancanti'},
        [pscustomobject]@{Componente='Wireshark / tshark'; Stato=$(if(Test-Path "$env:ProgramFiles\Wireshark\tshark.exe"){'PRESENTE'}else{'MANCANTE'}); Azione='Installazione tramite winget'},
        [pscustomobject]@{Componente='Nmap'; Stato=$(if((Test-Path "${env:ProgramFiles(x86)}\Nmap\nmap.exe") -or (Get-Command nmap.exe -ErrorAction SilentlyContinue)){'PRESENTE'}else{'MANCANTE'}); Azione='Installazione tramite winget'},
        [pscustomobject]@{Componente='Npcap'; Stato=$(if(Test-Path "$env:WINDIR\System32\Npcap\wpcap.dll"){'PRESENTE'}else{'MANCANTE'}); Azione='Se manca, completare il setup driver: https://npcap.com/#download'},
        [pscustomobject]@{Componente='Tailscale'; Stato=$(if(Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe"){'PRESENTE'}else{'MANCANTE'}); Azione='Installa se manca; accesso account da completare per il remoto'},
        [pscustomobject]@{Componente='M3 installato'; Stato=$(if(Test-Path "$InstallRoot\installed_release.json"){'PRESENTE - USARE UPDATE'}else{'NUOVA INSTALLAZIONE DA VERIFICARE'}); Azione='Nessuna sovrascrittura di installazioni esistenti'},
        [pscustomobject]@{Componente='Licenza M3'; Stato='DA VERIFICARE NELL APP'; Azione='Attivazione dopo installazione'}
    )
    Write-Host "`nCHECKLIST INSTALLAZIONE M3PRO" -ForegroundColor Cyan
    $rows | Format-Table -AutoSize -Wrap | Out-Host
    Write-Utf8 (Join-Path $Work 'checklist.json') ($rows | ConvertTo-Json)
    if ($StatusFile) {
        Write-Utf8 $StatusFile (@{checklist=$rows;log_directory=$Work} | ConvertTo-Json -Depth 5)
    }
}
function Validate-Manifest($Manifest) {
    if ($Manifest.schema -ne 1 -or $Manifest.channel -ne 'stable' -or $Manifest.prerelease -ne $false -or
        $Manifest.version -notmatch '^\d+\.\d+\.\d+$' -or
        $Manifest.commit -notmatch '^[a-fA-F0-9]{40}$' -or
        $Manifest.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        $Manifest.zip_name -notmatch '^[a-zA-Z0-9._-]+\.zip$' -or
        [long]$Manifest.size -le 0 -or [long]$Manifest.size -gt 2147483648) {
        throw 'Manifest ufficiale non valido: installazione interrotta.'
    }
    if ($Manifest.release_id -ne ($Manifest.version + '+' + $Manifest.commit.Substring(0,7)) -or
        $Manifest.approval.release_id -ne $Manifest.release_id -or
        -not $Manifest.approval.approved_by -or -not $Manifest.approval.approved_at -or
        $Manifest.approval.sha256 -ne $Manifest.sha256) { throw 'Approvazione release non coerente.' }
}
function Expand-Safe([string]$Zip, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $prefix = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $seen = @{}
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('/','\')
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $name))
            if ($name.Contains(':') -or $name.StartsWith('\') -or
                -not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
                $seen.ContainsKey($target) -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) {
                throw "Percorso ZIP non valido: $name"
            }
            $seen[$target] = $true
            if ($name.EndsWith('\')) { [IO.Directory]::CreateDirectory($target) | Out-Null; continue }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
        }
    } finally { $archive.Dispose() }
}

try {
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'Windows x64 richiesto.' }
    if (-not $CheckOnly -and -not $ChecklistOnly) {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Aprire PowerShell come amministratore e rilanciare lo stesso comando.'
        }
        if ($ConfigFile) {
            $ConfigFile = (Resolve-Path -LiteralPath $ConfigFile).Path
            $PrivateConfig = [IO.File]::ReadAllText($ConfigFile)
        }
        # Mai cancellare o resettare un M3 esistente, neppure dopo un errore.
        if ((Test-Path $InstallRoot) -and @(Get-ChildItem -LiteralPath $InstallRoot -Force).Count -gt 0) {
            $machineFiles = @('backend\.env','m3-python-path.txt','installed_release.json','m3-update-local.json','.venv','.runtime','frontend\node_modules','sessions','reports','logs','licenses.json','license.json')
            $configured = @($machineFiles | Where-Object { Test-Path (Join-Path $InstallRoot $_) }).Count -gt 0
            if ($configured -or -not (Test-Path "$InstallRoot\.git")) {
                throw 'C:\MEFF contiene gia file di installazione. Per M3 installato usare Update. I dati esistenti non vengono sovrascritti.'
            }
        }
    }
    New-Item -ItemType Directory -Path $Work | Out-Null
    Start-Transcript -Path (Join-Path $Work 'installazione.log') | Out-Null
    Show-InstallationChecklist
    if ($ChecklistOnly) {
        Write-Host "Solo controllo, nessuna installazione. Checklist salvata in $Work"
        Stop-Transcript | Out-Null
        exit 0
    }
    Write-Host 'Scarico e verifico ultima versione ufficiale M3PRO...'
    $Manifest = Invoke-RestMethod -Uri "$Feed/m3pro-stable-manifest.json" -TimeoutSec 60
    Validate-Manifest $Manifest
    if ($Manifest.requires.os -and $Manifest.requires.os -ne 'windows') { throw 'Release non destinata a Windows.' }
    if ($Manifest.requires.python_minimum -and [version]$Manifest.requires.python_minimum -gt [version]'3.12.0') {
        throw 'La nuova release richiede un runtime superiore: aggiornare questo installer prima di proseguire.'
    }
    $Zip = Join-Path $Work $Manifest.zip_name
    # Il pacchetto deve provenire dallo stesso feed pubblico configurato.
    Invoke-WebRequest -UseBasicParsing -Uri "$Feed/$($Manifest.zip_name)" -OutFile $Zip -TimeoutSec 600
    if ((Get-Item $Zip).Length -ne [long]$Manifest.size -or (Get-FileHash $Zip -Algorithm SHA256).Hash -ne $Manifest.sha256) {
        throw 'Dimensione o SHA256 del pacchetto non corrispondono alla release approvata.'
    }
    $Stage = Join-Path $Work 'release'
    Expand-Safe $Zip $Stage
    foreach ($file in @('VERSION','backend/server.py','frontend/build/index.html','m3_launcher.py','m3_runtime.py','m3_updater.py','AVVIA-M3PRO.vbs')) {
        if (-not (Test-Path (Join-Path $Stage $file) -PathType Leaf)) { throw "Pacchetto incompleto: manca $file" }
    }
    if ((Get-Content (Join-Path $Stage 'VERSION') -Raw).Trim() -ne $Manifest.version) { throw 'VERSION non coerente con il manifest.' }
    Write-Host "Verificata release ufficiale $($Manifest.version), SHA256 corretto."
    if ($CheckOnly) {
        Write-Host "Verifica completata, nessun servizio o programma installato. File: $Work"
        Stop-Transcript | Out-Null
        exit 0
    }
    if (Get-NetTCPConnection -State Listen -LocalPort 3000,5556,8001 -ErrorAction SilentlyContinue) {
        throw 'Una porta M3 e gia occupata. Nessun processo e stato arrestato: chiudere l applicazione interessata prima di installare.'
    }
    $PythonBase = Find-Python312
    if (-not $PythonBase) { Install-Winget 'Python.Python.3.12'; $PythonBase = Find-Python312 }
    if (-not $PythonBase) { throw 'Python 3.12 x64 non trovato dopo installazione.' }
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { Install-Winget 'OpenJS.NodeJS.LTS' }
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'Node.js/npm non disponibile.' }
    if ((Test-Path $InstallRoot) -and @(Get-ChildItem -LiteralPath $InstallRoot -Force).Count -gt 0) {
        # Destinazione fissa verificata, fuori dalla cartella da archiviare; nessuna eliminazione.
        $Backup = 'C:\MEFF-sorgenti-' + [guid]::NewGuid().ToString('N')
        if ([IO.Path]::GetFullPath($InstallRoot) -ne 'C:\MEFF' -or -not $Backup.StartsWith('C:\MEFF-sorgenti-')) { throw 'Percorso archivio non valido.' }
        Set-Location $Work
        Move-Item -LiteralPath $InstallRoot -Destination $Backup
        Write-Host "Clone originale conservato in $Backup"
    }
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $Stage -Force | Copy-Item -Destination $InstallRoot -Recurse
    # Conserva questo bootstrap corretto: lo ZIP puo contenere un installer precedente.
    Write-Utf8 (Join-Path $InstallRoot 'INSTALLA-MEFF.ps1') $BootstrapSource
    Write-Host 'Preparo ambiente Python dedicato a M3...'
    Run-Checked $PythonBase @('-m','venv',"$InstallRoot\.venv")
    $Python = "$InstallRoot\.venv\Scripts\python.exe"
    Run-Checked $Python @('-m','pip','install','--upgrade','pip')
    # Un unico resolver; non usare requirements.txt cloud (contiene pin incompatibili Windows).
    $Packages = @('fastapi==0.110.1','uvicorn==0.34.0','motor==3.7.0','pymongo==4.11.1','pydantic[email]==2.11.5','pydantic-settings==2.9.1','python-dotenv','PyJWT','python-jose[cryptography]','passlib','bcrypt==4.1.3','python-multipart','aiofiles','aiohttp','httpx>=0.28,<0.29','requests','qrcode','reportlab==4.4.4','Pillow==11.3.0','PyMuPDF','psutil==5.9.8','scapy==2.6.1','numpy==2.2.6','pandas==2.2.3','python-nmap','twilio','openai==1.99.9','litellm==1.78.0','google-genai==1.44.0','protobuf==5.29.5','boto3','PyYAML','python-dateutil','windows-curses','python-evtx','python-registry','mitmproxy==11.0.2','mvt==2.6.0','emergentintegrations==0.1.0','https://github.com/EC-DIGIT-CSIRC/sysdiagnose/archive/1180bcb8ac954db64980038ce714db2dad8a1832.zip')
    Run-Checked $Python (@('-m','pip','install','--extra-index-url','https://d33sy5i8bnduwe.cloudfront.net/simple/') + $Packages)
    Run-Checked $Python @('-m','pip','check')
    Run-Checked $Python @('-c','import uvicorn, fastapi, motor, pymongo, reportlab, scapy, psutil, sysdiagnose, mitmproxy, mvt, fitz, jwt; from emergentintegrations.llm.chat import LlmChat')
    Write-Utf8 "$InstallRoot\m3-python-path.txt" ($Python + "`n")
    # Solo il server statico: la UI e gia compilata e verificata nello ZIP ufficiale.
    $Serve = Join-Path $Work 'static-server'
    New-Item -ItemType Directory -Path $Serve | Out-Null
    Run-Checked 'npm.cmd' @('install','--prefix',$Serve,'--no-audit','--no-fund','serve@14.2.4')
    Copy-Item -LiteralPath "$Serve\node_modules" -Destination "$InstallRoot\frontend\node_modules" -Recurse
    Write-Utf8 "$InstallRoot\m3-update-local.json" (@{channel='stable';feed_base_url=$Feed;install_enabled=$true} | ConvertTo-Json)
    if ($ConfigFile) { Write-Utf8 "$InstallRoot\backend\.env" $PrivateConfig }
    else {
        $bytes = New-Object byte[] 48
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        $secret = [Convert]::ToBase64String($bytes)
        Write-Utf8 "$InstallRoot\backend\.env" "JWT_SECRET=$secret`nM3_ADMIN_USER=admin`nM3_ADMIN_PASS=$secret`nAPP_URL=https://pc-network-scan.emergent.host`nPAYPAL_ENABLED=false`nCORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000`n"
    }
    $Notes = New-Object 'System.Collections.Generic.List[string]'
    # Modulo legacy: nessuna compilazione C++ automatica sul PC del cliente.
    try { Run-Checked $Python @('-m','pip','install','--only-binary=:all:','netifaces==0.11.0') }
    catch { $Notes.Add('netifaces: wheel compatibile non disponibile; enumerazione rete tramite psutil. Il controllo strumenti PRO puo segnalarlo come mancante.') }
    if (-not $SkipExternalTools) {
        foreach ($tool in @(
            @{Id='WiresharkFoundation.Wireshark';Path="$env:ProgramFiles\Wireshark\tshark.exe"},
            @{Id='Insecure.Nmap';Path="${env:ProgramFiles(x86)}\Nmap\nmap.exe"},
            @{Id='Tailscale.Tailscale';Path="$env:ProgramFiles\Tailscale\tailscale.exe"}
        )) {
            if (-not (Test-Path $tool.Path)) {
                try { Install-Winget $tool.Id; if (-not (Test-Path $tool.Path)) { throw 'Eseguibile non trovato dopo setup.' } }
                catch { $Notes.Add("$($tool.Id): da completare ($($_.Exception.Message))") }
            }
        }
    } else { $Notes.Add('Installazione strumenti di rete saltata su richiesta.') }
    if (-not (Test-Path "$env:WINDIR\System32\Npcap\wpcap.dll")) { $Notes.Add('Npcap: completare il driver di cattura da https://npcap.com/#download prima delle scansioni traffico.') }
    $sh = New-Object -ComObject WScript.Shell
    $link = $sh.CreateShortcut((Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'M3PRO.lnk'))
    $link.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $link.Arguments = '"C:\MEFF\AVVIA-M3PRO.vbs"'
    $link.WorkingDirectory = $InstallRoot
    $link.Save()
    # Autostart silenzioso per l'utente corrente, senza rimuovere altri servizi.
    $vbs = @'
Set sh=CreateObject("WScript.Shell")
sh.CurrentDirectory="C:\MEFF"
sh.Run Chr(34) & "C:\MEFF\.venv\Scripts\python.exe" & Chr(34) & " " & Chr(34) & "C:\MEFF\m3_launcher.py" & Chr(34) & " --mode background", 0, False
'@
    Write-Utf8 "$InstallRoot\M3-START-BACKGROUND.vbs" $vbs
    $startup = $sh.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'M3PRO-Background.lnk'))
    $startup.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $startup.Arguments = '"C:\MEFF\M3-START-BACKGROUND.vbs"'
    $startup.WorkingDirectory = $InstallRoot
    $startup.Save()
    Write-Utf8 "$InstallRoot\installed_release.json" (@{version=$Manifest.version;release_id=$Manifest.release_id;commit=$Manifest.commit;sha256=$Manifest.sha256;channel='stable';installed_at=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json)
    Start-Process -FilePath $Python -ArgumentList '"C:\MEFF\m3_launcher.py" --mode app' -WorkingDirectory $InstallRoot -WindowStyle Hidden
    $Ready = $false
    for ($attempt=0; $attempt -lt 45; $attempt++) {
        & $Python "$InstallRoot\m3_launcher.py" --mode check *> (Join-Path $Work 'servizi.log')
        if ($LASTEXITCODE -eq 0) { $Ready = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $Ready) { throw "File installati, servizi non tutti pronti. Consultare $Work e C:\MEFF\logs." }
    $Notes.Add('Attivare la licenza in M3 e completare accesso Tailscale per il remoto.')
    if (-not $ConfigFile) { $Notes.Add('Configurazione privata non importata: le integrazioni che richiedono credenziali devono essere configurate dal tecnico.') }
    Write-Utf8 "$InstallRoot\ESITO-INSTALLAZIONE.txt" ($Notes -join "`r`n")
    Show-InstallationChecklist
    Copy-Item -LiteralPath (Join-Path $Work 'checklist.json') -Destination "$InstallRoot\CHECKLIST-INSTALLAZIONE.json" -Force
    Write-Host "M3PRO $($Manifest.version) avviato. Aggiornamenti successivi dal canale ufficiale."
    $Notes | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Host "INSTALLAZIONE NON COMPLETATA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Log e file diagnostici: $Work. Nessuna cartella esistente viene eliminata."
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

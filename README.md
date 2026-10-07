# M3PRO Setup Windows

Solo installer pubblico. I sorgenti applicativi sono nel repository privato M3proFinalversion.

## Un comando, nessun file da copiare manualmente

Apri PowerShell su Windows 10/11 x64 e incolla:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Maxbeta77/M3proSetup/main/AVVIA.ps1 | iex"
```

Conferma la richiesta amministratore di Windows. Il setup grafico controlla il PC; premi **INSTALLA M3PRO** per procedere. Il comando scarica automaticamente un file temporaneo, ne verifica lo SHA256 e avvia la finestra M3PRO. Il motore verifica poi la release ufficiale e scarica i programmi necessari.

La finestra mostra la checklist e i dettagli reali dell'operazione. Non sovrascrive un M3 gia configurato: sulle macchine esistenti usare Update. Driver Npcap, login Tailscale e attivazione licenza possono richiedere completamento interattivo. winget serve per i prerequisiti mancanti.

## Verifiche disponibili

`INSTALLA-MEFF.ps1 -ChecklistOnly`: controlla senza installare.

`INSTALLA-MEFF.ps1 -CheckOnly`: scarica e verifica il pacchetto ufficiale senza installare.

`AVVIA.ps1 -DownloadOnly`: scarica e verifica soltanto il setup grafico.

`INSTALLA-M3-GUI.ps1 -CheckOnly`: apre la finestra di controllo con installazione disabilitata.

La grafica e il controllo del download sono stati verificati. La prova di installazione completa su una macchina pulita resta necessaria.

## Setup 2026-10-07-3

Runtime Microsoft Visual C++ x64 per i PDF e avanzamento percentuale per fasi; il 100% arriva dopo la verifica servizi. AVVIA.ps1 -ResumeIncomplete recupera solo una nuova installazione interrotta prima della configurazione. Confronta i file con la release ufficiale e conserva integralmente la cartella precedente. Rifiuta installazioni configurate o file aggiuntivi.


Setup 2026-10-07-4: collegamento M3PRO sul desktop pubblico, icona del prodotto e verifica del collegamento salvato. Il setup rispetta la sospensione del feed ufficiale: non installa release ritirate.

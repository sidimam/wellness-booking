# Registro delle modifiche — Wellness Booking

Una voce per ogni modifica, la più recente in alto, raggruppate per giorno. Serve a ricostruire lo stato del progetto
senza rileggere le conversazioni: ogni commit aggiunge qui la sua voce (cosa, perché, dove, come è stato provato).
Le voci fino al 16/11/2026 sono ricostruite dalla storia git (messaggio del commit e hash).

## 2026-11-16
- **Wiki: nuova pagina `Changelog.md`** in inglese (come le wiki di wellness-gateway e Unraid Drive), una sezione per build TestFlight ricavata dai 35 commit, con link in `_Sidebar.md` e in `Home.md`; rimanda a questo `changelog.md` per il dettaglio dei commit. Controllato: nessun rimando al vecchio `CHANGELOG.md` nelle cartelle WellnessBooking e WellnessGateway.
- Nuovo `changelog.md`: storia ricostruita dai commit (strumento `tools/changelog_da_git.sh` della cartella Claude); da qui in poi ogni commit aggiunge la sua voce in cima.

## 2026-11-07
- release.sh: kit App Store Connect relativo al repo invece del percorso fisso di LocalData (`9abfe98`)

## 2026-10-31
- 1.2.0 (25): two opening attempts shown (Prenoto … e alle …), second time in the rule editor, today's classes stay visible (ended greyed, participants only), member classes upcoming/past with cyclic class↔member navigation; Debug -mockGateway for simulator tests (`67d1811`)

## 2026-10-29
- 1.2.0 (24): tap a member photo to enlarge it (pinch/double tap), name and surname as headline with nickname below; Debug -demoParticipants screen for simulator tests (`c8e926e`)
- 1.2.0 (23): members show first and last name from the gateway (public profiles), search by name (`d58ffe0`)
- 1.2.0 (22): stima dell'orario come il gateway, mai prima dell'apertura comunicata dal centro (`df5dbba`)
- 1.2.0 (21): regole del gateway con data di validità e limite settimanale (Reformer 07:01 dal 1/11, max 2 a settimana); orario previsto dalle regole del gateway nella scheda lezione (`14a9b08`)

## 2026-10-12
- 1.2.0 (20): Persone del centro (classifica MOVEs settimanale/mensile, compagni di corso, scheda socio con storico) e sezione Partecipanti nella scheda lezione (`1a599ce`)

## 2026-10-10
- 1.1.0 (19): scheda profilo leggibile (nome e cognome insieme, date e lingua formattate, unità tradotte, ID e dati tecnici a scomparsa) (`a358486`)

## 2026-10-09
- 1.1.0 (18): Rimuovi disdice anche su mywellness (prenotazione o lista d'attesa), conferma e riepilogo; Stop ricorrenza disdice le future (`be917a0`)

## 2026-10-08
- 1.1.0 (17): impostazioni dello scheduler personali per ogni utente (modificabili da tutti, Torna alle predefinite) (`f4a9d21`)
- 1.1.0 (16): Scheduler del gateway scorre anche per gli utenti non amministratori (disabilitati solo i controlli, non la Form) (`7b29341`)
- 1.1.0 (15): etichette per i campi reali del profilo mywellness (nome account, lingua, impostazioni regionali, fuso orario), ID tecnici nascosti (`0c603ba`)
- 1.1.0 (14): più centri Technogym per account (selettore centro, sezione Centri nel profilo, aggiungi/rimuovi centro); release con chiave API ASC (`107e204`)
- 1.1.0 (13): scheda Il mio profilo mywellness (tutti i dati Technogym), impostazioni osservazione (normale/vicino alla lezione), testi quota separata (`098e09c`)

## 2026-10-07
- 1.1.0 (12): connessione al gateway stabile (refresh al rientro in primo piano, doppio tentativo health, nessun logout per 401 sporadici, polling anche se avviata offline) (`b3eee66`)

## 2026-10-04
- 1.1.0 (11): isolamento utente (login selfOnly), stato gateway solo in Altro, contatori nel footer, versione (`78d2907`)
- Scheduler gateway: intervallo minimo 15 s (allineato a v0.1.11) (`84a996b`)
- 1.1.0 (10): limiti per regola con contatori, ora della regola sempre applicata (`354dc93`)

## 2026-10-03
- 1.1.0 (9): fix rimozione lezioni (id doppiamente codificato), flag 'solo prenotabili' in barra, regole con nome prioritarie (`4412ac7`)
- 1.1.0 (8): identità e foto profilo mywellness, avatar; menu profili solo per amministratori (`971f40f`)
- 1.1.0 (7): esci dalla lista d'attesa, occhio sui campi password (`232b82e`)
- 1.1.0 (6): profilo personale di default (salvo scelta esplicita), elementi filtrati per profilo, check gateway online via /healthz, scheda gateway solo in Altro (`67097b0`)
- 1.1.0 (5): invito a collegare il proprio account mywellness, avviso quando si vede il profilo di un altro (`50ebfaa`)
- 1.1.0 (4): connessione tramite Cloudflare Access (service token), messaggi d'errore Access (`5b8a6b2`)
- 1.1.0 (3): profilo personale dell'utente del gateway selezionato di default, toggle 'È il mio account mywellness' (`e5ea735`)
- README 1.1 (`b996b2c`)
- 1.1.0 (2): modalità server wellness-gateway (profili multipli, prenotazioni 24h, disdetta anche di prenotazioni esterne, sync disdette, push APNs), immagini classi, solo iPhone+Watch, LAN http, traduzioni (`32ef100`)
- release.sh: firma cloud con la sessione Xcode, app id ASC; README TestFlight (`16babe4`)
- scripts/release.sh: archive, export e upload su TestFlight (`d4a8839`)
- Regole di apertura: nomi inseriti dall'utente, regola vuota ignorata (`6c0a6c6`)
- Widget multi-misura, App Intents, azioni rapide, lingue en/es/fr/de, regole di apertura per classe, Password AutoFill, background tasks, licenza MIT (`377f3e4`)
- README: scheda lezione e limite prenotazioni (`d9fbe69`)
- Scheda lezione con scheduler, giorni di anticipo regolabili, limite prenotazioni attive (5), 'Osservazione' al posto di watchdog, elenco completo classi (`1022a87`)
- Wellness Booking: app iOS + Watch per prenotazione automatica lezioni mywellness (`802e9c8`)

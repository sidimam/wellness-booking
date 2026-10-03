# Wellness Booking

App iOS (SwiftUI, iOS 17+) con companion Apple Watch che prenota da sola le lezioni di un centro
Technogym **mywellness** (es. Wellness Town, Roma) all'apertura delle prenotazioni e, se la classe è
piena, tiene un **osservazione** che prende al volo i posti che si liberano.

## Funzioni

- **Lezioni**: scopre tutte le lezioni del centro nei prossimi N giorni (filtro predefinito "Reformer"),
  mostra posti liberi, stato (piena / lista d'attesa / apre il …), istruttore e sala. Selezione multipla,
  aggiunta "solo queste date" oppure **ogni settimana** (stesso giorno e ora).
- **Scheduler**: prenota nell'istante di apertura (per Wellness Town: 3 giorni prima alle 05:00, letto
  dall'API `bookingOpensOn`), con anticipo configurabile in ms e ritentativi ravvicinati per N secondi.
  Orario personalizzato (ora + giorni prima) in Altro → Scheduler.
- **Osservazione**: se la classe è piena l'app entra in lista d'attesa (mywellness **non** prenota
  automaticamente dalla lista: avvisa soltanto) e interroga il calendario ogni N secondi, più fitto nelle
  ultime ore utili (la disdetta è possibile fino a 2 h prima). Appena `availablePlaces > 0` chiama `Book`
  e manda una **notifica prioritaria** (Time Sensitive, passa Focus/Non disturbare, arriva su Apple Watch).
- **Scheda lezione**: toccando una lezione si vede quando l'app prenoterà (apertura comunicata dal centro o giorni/ora
  impostati) e si attiva la prenotazione automatica singola o settimanale. Il cerchio a sinistra serve per la selezione multipla.
- **Limite prenotazioni attive**: default 5 (regola del centro, modificabile in Altro → Centro). Il conteggio include le
  prenotazioni fatte direttamente su mywellness (`isParticipant` dal calendario letto con il login).
- **Account**: login con le credenziali mywellness (Keychain). Centro configurabile tramite URL del widget.
- **Apple Watch**: stato delle lezioni seguite, Avvia/Ferma motore, Aggiorna (WatchConnectivity).
- **Altro**: colore app + icona alternativa (7 colori, Icon Composer), tema chiaro/scuro, iCloud KVS
  (impostazioni e lezioni, non la password), notifiche di prova, registro attività esportabile, walkthrough.

## Limite iOS da conoscere

iOS non esegue un'app in background a un orario preciso. Per prenotare alle 05:00 in punto e far girare
il osservazione l'app deve restare **in primo piano** (tiene lo schermo acceso da sola: iPhone in carica,
app aperta). In background resta solo il *BGAppRefresh* best-effort (iOS decide quando) e un promemoria
3 minuti prima dell'apertura.

## API mywellness usate (ricavate dal bundle del widget)

| Scopo | Endpoint |
|---|---|
| Login | `POST https://core.mywellness.com/v2/enduser/authentication/login` `{username,password,keepMeLoggedIn}` → `token`, `userContext.id` |
| Centro | `GET https://core.mywellness.com/v2/enduser/facility/detail?facilityUrl=…` |
| Calendario | `GET https://calendar.mywellness.com/v2/enduser/class/Search?eventTypes=Class&facilityId=…&fromDate=YYYY-MM-DD&toDate=…` (pubblico; con Bearer popola `isParticipant`) |
| Prenota | `POST https://calendar.mywellness.com/v2/enduser/class/Book` `{partitionDate:YYYYMMDD,userId,classId,station:null}` → `result` ∈ Booked, UserAddedToWaitingList, PlaceNotAvailable, ToMuchParticipants, Failed |
| Disdici | `POST https://calendar.mywellness.com/v2/enduser/class/Unbook` |

Header su ogni chiamata: `X-MWAPPS-APPID: EC1D38D7-D359-48D0-A60C-D8C0B8FB9DF9`, `X-MWAPPS-CLIENT: enduserweb`,
`X-MWAPPS-CLIENTVERSION`, `Authorization: Bearer <token>`, query `_c=it-IT`.

## Build

```bash
xcodegen generate
xcodebuild -project WellnessBooking.xcodeproj -scheme WellnessBooking \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Icone: `swift scripts/make_icons.swift "$PWD"` rigenera glifo, appiconset e documenti `.icon`.

### Installazione su iPhone (sviluppo)

```bash
xcodebuild -project WellnessBooking.xcodeproj -scheme WellnessBooking \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> <path>/Wellness\ Booking.app
```

### TestFlight

Archive da Xcode (Product → Archive → Distribute → TestFlight) oppure `xcodebuild archive` +
`-exportArchive` con `ExportOptions.plist` (`app-store-connect`, team `X5SR67A8AL`) e upload con
`xcrun altool --upload-app`. Prima di archiviare: `xattr -cr .`.

Struttura: `WellnessBooking/` (Core + Views iOS), `Watch/`, `Icons/*.icon`, `SupportFiles/`, `scripts/`.

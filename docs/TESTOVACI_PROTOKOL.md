# Testovací protokol

**Prostředí ověření:**
- **OS:** macOS 27.2 (Build `26B123`)
- **Architektura:** Apple Silicon (`arm64-apple-macosx18.0`)
- **Toolchain:** Apple Swift 6.1.2 (`/Library/Developer/CommandLineTools`, bez plného Xcode)
- **Datum:** 14. listopadu 2026

## 1. Automatizované testy (`swift test`)

Spouštěno přes Swift Testing (`OdkladisteCoreTests.swift`):

| Test | Výsledek | Ověřeno |
|---|---|---|
| `deduplicationAndCrossShelfSharing` | Prošlo | Deduplikace v jedné poličce (i v jedné dávce), stejný soubor v různých poličkách, stejně pojmenované soubory z různých složek |
| `persistenceBackupRecoveryAndCorruptionPreservation` | Prošlo | Atomický zápis, obnova ze `state.backup.json` při poškození `state.json`, zachování `state.corrupted.*` |
| `externalTransferTransactionSafetyAndIdempotency` | Prošlo | Souběžné přidání položky během přenosu, opakovaný callback (idempotence) |
| `externalMoveVerificationHandlesUnverifiableAndConfirmedMoves` | Prošlo | Okamžité i asynchronní potvrzení `.move`, fallback na `unverifiable` a ruční rozhodnutí |
| `internalShelfMoveAndCopy` | Prošlo | Přesun reference mezi poličkami bez zásahu do originálu na disku, ochrana proti dvojímu odebrání |
| `displayPlacementClampsDisconnectedMonitor` | Prošlo | Oříznutí polohy okna na zbývající displej po odpojení externího monitoru |
| `undoRedoForEmptyAndShelfTransfers` | Prošlo | Undo/Redo po přesunu mezi poličkami i po vyprázdnění, zachování souboru na disku |

## 2. Ruční ověření na macOS (`build/Odkladiste.app`)

| Scénář | Stav | Poznámka |
|---|---|---|
| Dvě a více nezávislých poliček, přesun za hlavičku, změna velikosti | Ověřeno | Přidán úchyt pro změnu velikosti v pravém dolním rohu; u neaktivního panelu macOS neaktualizuje kurzor na hraně |
| Příjem souborů z Finderu a zobrazení Quick Look náhledů v mřížce | Ověřeno | Mřížka s náhledy PNG/SVG funguje |
| Výdej souboru do Finderu (`.move`) | Ověřeno | Po úpravě asynchronního ověření zmizení z původní cesty se položka správně automaticky odebrala |
| Menu bar popover (barvy, přejmenování, připnutí, skrývání bez zavírání nabídky) | Ověřeno | Přechod z `NSMenu` na `NSPopover` udržuje nabídku otevřenou během úprav |
| Výdej do Mailu, odpojení druhého monitoru, přepínání Spaces / Fullscreen, iCloud placeholder | Neověřeno v této relaci | Doporučeno otestovat ručně na konkrétní sestavě uživatele |
| Sestavení klasického `.xcodeproj` přes `xcodebuild` | Neověřeno | Na stroji není nainstalován plný Xcode (sestaveno přes SwiftPM + `scripts/build-app.sh`) |

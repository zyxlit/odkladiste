# Architektura, datový formát a oprávnění

## 1. Členění kódu

Projekt je rozdělen na dva moduly v `Package.swift`:

- **`OdkladisteCore`** (`Sources/OdkladisteCore/`) — platformně nezávislá doménová logika testovatelná bez oken:
  - `Models.swift`: datový model (`AppState`, `Shelf`, `ShelfItem`, `WindowPlacement`, `TransferOperation`, `InternalDragPayload`).
  - `PersistenceService.swift`: atomický zápis JSONu, zálohování a obnova.
  - `BookmarkService.swift`: tvorba a rozlišení URL bookmarků, extrakce identity souboru `(volumeIdentifier, fileResourceIdentifier)`.
  - `DisplayPlacement.swift`: výpočet a oříznutí pozice oken při změně monitorů.
  - `ShelfStore.swift`: `@MainActor` store spravující poličky, deduplikaci, Undo/Redo a transakce předání.
- **`Odkladiste`** (`Sources/Odkladiste/`) — nativní macOS vrstva (AppKit + SwiftUI):
  - `OdkladisteApp.swift`: start aplikace (`NSApp.setActivationPolicy(.accessory)`), menu bar (`NSStatusItem` + `NSPopover`), koordinace panelů a okno Nastavení.
  - `ShelfPanelController.swift`: životní cyklus `NSPanel` (`.nonactivatingPanel`, `becomesKeyOnlyIfNeeded = true`), klávesové zkratky aktivního panelu, sledování displejů (`CGDisplayCreateUUIDFromDisplayID`).
  - `ShelfContentView.swift`: AppKit `NSDraggingDestination` / `NSDraggingSource`, SwiftUI mřížka/seznam, hlavička s přesunem okna a úchyt pro změnu velikosti.
  - `MenuBarPopoverView.swift`: interaktivní popover menu baru s vyhledáváním a inline správou poliček.
  - `ThumbnailService.swift`: asynchronní Quick Look náhledy (`QLThumbnailGenerator`) s omezenou `NSCache` (max. 300 položek / 64 MB).
  - `QuickLookService.swift`: nativní `QLPreviewPanel` na `Mezerník`.
  - `HotkeyService.swift`: globální zkratky přes Carbon `RegisterEventHotKey`.
  - `SettingsView.swift`: okno Nastavení (Obecné, Vzhled, Zkratky).

## 2. Datový formát a bezpečnost ukládání

- **Umístění dat:** `~/Library/Application Support/Odkladiste/state.json`
- **Záloha:** před každým novým zápisem se předchozí `state.json` uloží jako `state.backup.json` a nový soubor se zapíše atomicky přes dočasný soubor (`replaceItemAt`).
- **Ochrana při poškození:** pokud se nepodaří načíst `state.json`, aplikace jej přesune na `state.corrupted.<timestamp>.json` a obnoví stav ze zálohy `state.backup.json`. Pokud jsou poškozené oba soubory, oba se uloží bokem a nikdy se tiše nepřepíší prázdným stavem.
- **Uživatelská předvolba vzhledu:** uložena v `UserDefaults` (`odkladiste.*`).
- **Reference vs. data:** v `ShelfItem` se ukládá pouze `bookmarkData` a `lastKnownURL`, nikdy obsah souborů.

## 3. Transakční model výdeje (`TransferOperation`)

1. Před zahájením `NSDraggingSession` vznikne `TransferOperation` s vlastním UUID a neměnným seznamem ID předávaných položek.
2. Odchozí `NSPasteboardItem` nese jak vlastní typ `app.odkladiste.internal-items`, tak standardní `fileURL`.
3. Při puštění do jiné poličky Odkladiště se uplatní interní transakce (přesun nebo `Option`-kopie reference) a externí callback `endedAt` se ignoruje.
4. Při puštění do externí aplikace (`draggingSession(_:endedAt:operation:)`):
   - `[]` → zrušeno/odmítnuto, nic se neodebírá.
   - `.copy` → předání potvrzeno, odeberou se pouze položky dané operace (mezitím nově přidané položky zůstávají).
   - `.move` → Finder provádí přesun asynchronně těsně po `endedAt`; položky stále přítomné na původní cestě přecházejí do `.inProgress` a krátce se ověří jejich skutečné zmizení z původní cesty. Pokud na původní cestě zůstanou, přecházejí do `unverifiable` s výzvou *„Předání nelze ověřit — Odebrat / Ponechat“*.

## 4. Oprávnění, sandbox a podpis

- **App Sandbox:** vypnutý (přímá open-source distribuce). Umožňuje spolehlivou kontrolu přesunutých souborů i bez opakovaného `NSOpenPanel` oprávnění. Případná budoucí verze pro Mac App Store vyžaduje zapnutí App Sandboxu a `.withSecurityScope` u bookmarků.
- **Soukromí:** aplikace nepoužívá Full Disk Access, Accessibility ani Input Monitoring. Neprovádí žádné síťové přenosy ani analytiku (jediný externí odkaz v Nastavení se otevírá v prohlížeči až po kliknutí uživatele).
- **Podpis a Gatekeeper:** lokální build skript `scripts/build-app.sh` používá ad-hoc podpis (`codesign --force --deep --sign -`). Pro veřejnou distribuci binárního DMG mimo vlastní sestavení ze zdrojového kódu je nutný placený certifikát **Developer ID Application** a notarizace u Apple.

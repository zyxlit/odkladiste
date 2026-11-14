# Etapa A — Technický prototyp a ověření rizik

Tento dokument zaznamenává architektonická rozhodnutí a plán ověření pro Etapu A podle [ODKLADISTE_SPEC.md](../ODKLADISTE_SPEC.md).

## 1. Rozhodnutí o prostředí, sandboxu a podpisu

- **Minimální macOS:** `macOS 14.0` (Sonoma), cílová architektura `arm64` (Apple Silicon).
- **Build systém:** Swift Package Manager (`Package.swift`) + skript `scripts/build-app.sh` pro zabalení nativního `.app` bundle (`LSUIElement = true`). Na vývojovém stroji je k dispozici Swift 6.1.2 a Command Line Tools (bez plného Xcode).
- **App Sandbox:** Pro Etapu A a přímou open-source distribuci je **App Sandbox vypnutý**.
  - *Důvod:* Umožňuje spolehlivou práci se standardními file URL, přímou kontrolu existence zdrojového souboru po `.move` operaci ve Finderu a budoucí explicitní „Kopírovat/Přesunout do složky…“ bez nutnosti opakovaně žádat security-scoped přístup k cílovým složkám.
  - *Důsledek:* Pro budoucí případnou distribuci v Mac App Store by bylo nutné zapnout App Sandbox, přidat `.withSecurityScope` k bookmarkům a vyvažovat `startAccessingSecurityScopedResource()`.
- **Podpis:** Lokální buildy používají ad-hoc podpis (`codesign --force --deep --sign -`). Pro veřejnou distribuci mimo GitHub zdrojový kód bude potřeba Developer ID podpis a notarizace.
- **Bundle ID:** Pro vývoj se používá pracovní identifikátor `local.odkladiste.prototype` (nastavitelný přes `ODKLADISTE_BUNDLE_ID`).

## 2. Co je implementováno v prototypu

- Dvě nezávislá plovoucí okna (`NSPanel` s `.nonactivatingPanel`, `becomesKeyOnlyIfNeeded = true`, `.floating` úroveň, `.canJoinAllSpaces`).
- Ikona v menu baru (`NSStatusItem`) bez ikony v Docku (`NSApp.setActivationPolicy(.accessory)`).
- Příjem existujících file URL z Finderu s deduplikací podle `(volumeIdentifier, fileResourceIdentifier)` a fallbackem na normalizovanou cestu.
- Výdej přes nativní `NSDraggingSession` (`NSPasteboardItem` nesoucí jak interní `app.odkladiste.internal-items`, tak standardní `fileURL`), maska `[.copy, .move]`.
- Transakční sledování předání (`TransferOperation` s UUID a neměnným seznamem ID položek):
  - `.cancelled` (`[]`) → nic se neodebírá.
  - `.copyConfirmed` → odeberou se pouze položky dané operace.
  - `.moveReported` → u každé položky se ověří, zda zmizela z původní cesty; pokud zůstává, přechází do stavu `unverifiable` s výzvou „Odebrat / Ponechat“.
- Atomické ukládání do `Application Support/Odkladiste/state.json` se zálohou `state.backup.json` a zachováním poškozených souborů jako `state.corrupted.<timestamp>.json`.
- Přepočet a oříznutí pozice oken při odpojení externího monitoru (`DisplayPlacement.resolveFrame`).

## 3. Co je potřeba ověřit ručně na macOS

- [ ] Sestavení a spuštění `build/Odkladiste.app` přes `./scripts/build-app.sh` a `open build/Odkladiste.app`.
- [ ] Přetažení souborů a složek z Finderu do obou poliček (včetně duplicity a stejně pojmenovaných souborů z různých složek).
- [ ] Přetažení souboru z poličky do **Finderu** (stejný svazek vs. `Option` pro kopii vs. jiný svazek) — sledovat v diagnostice poličky, jakou `NSDragOperation` Finder vrátí a zda u velkých souborů nedochází k předčasnému odebrání.
- [ ] Přetažení souboru z poličky do **Mailu** (nová rozepsaná zpráva) — ověřit přijetí přílohy a automatické odebrání z poličky.
- [ ] Přetažení mezi dvěma poličkami (výchozí přesun reference vs. `Option` kopie reference).
- [ ] Ukončení a znovuspouštění aplikace — obnova poliček, bookmarků, pozic a viditelnosti.
- [ ] Chování na dvou monitorech a po odpojení externího monitoru.

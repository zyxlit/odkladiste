# Changelog

Všechny významné změny v projektu Odkladiště.

## [1.0.0] — 2026-11-14

### Přidáno
- Více samostatných plovoucích poliček (`NSPanel`) s vlastní polohou, velikostí, názvem, barvou a připnutím.
- Nativní příjem a výdej souborů přes AppKit `NSDraggingSession` (podpora kopírování i přesunu, samostatný úchyt „Vše“).
- Transakční sledování předání (`TransferOperation`) včetně asynchronního ověření `.move` operací ve Finderu a bezpečného fallbacku *„Předání nelze ověřit“*.
- Přetahování mezi poličkami (přesun reference nebo `Option` pro kopii reference).
- Interaktivní menu bar popover s inline změnou barvy, připnutím, přejmenováním, vyhledáváním a přepínačem *Skrýt / Zobrazit všechny*.
- Kompaktní mřížka a seznam s asynchronními Quick Look náhledy (`QLThumbnailGenerator`) a volbou velikosti náhledů.
- Vícečetný výběr (`klik`, `Cmd+klik`, `Shift+klik`, `Cmd+A`), Quick Look (`Mezerník`), lokální filtrování (`Cmd+F`) a Zpět/Znovu (`Cmd+Z` / `Shift+Cmd+Z`).
- Globální klávesové zkratky (`Ctrl+Option+N`, `Ctrl+Option+O`) přes Carbon `RegisterEventHotKey` bez potřeby Accessibility oprávnění.
- Okno Nastavení (Obecné, Vzhled, Zkratky) včetně podpory spuštění po přihlášení (`SMAppService`).
- Atomická persistence stavu do `Application Support/Odkladiste/state.json` se zálohou a zachováním poškozených souborů.
- Lokalizace CS/EN (`Localizable.xcstrings`) a respektování Reduce Motion / Reduce Transparency.

# Přispívání do projektu Odkladiště

Děkujeme za zájem o vylepšení Odkladiště! Projekt vzniká jako čistá nativní macOS aplikace v Swiftu bez zbytečných závislostí.

## Lokální vývoj

1. Naklonuj repozitář.
2. Ověř testy:
   ```bash
   swift test
   ```
3. Sestav a spusť lokální aplikaci:
   ```bash
   ./scripts/build-app.sh
   open build/Odkladiste.app
   ```

## Pravidla pro změny

- **Bez síťových přenosů a telemetrie:** Aplikace nesmí odesílat žádná uživatelská data ani cesty k souborům.
- **Bezpečnost souborů:** Odebrání položky, vyprázdnění ani smazání poličky nesmí nikdy mazat původní soubory na disku.
- **Struktura kódu:** Doménová a perzistenční logika patří do `Sources/OdkladisteCore` (testovatelná bez UI), macOS/AppKit/SwiftUI vrstva do `Sources/Odkladiste`.
- **Žádná citlivá data:** Do repozitáře nepatří certifikáty, hesla ani osobní Apple Team ID.
- **Nové funkce:** Před větší změnou konceptu se podívej do [ODKLADISTE_SPEC.md](ODKLADISTE_SPEC.md) a [docs/ZNAME_LIMITY_A_P2.md](docs/ZNAME_LIMITY_A_P2.md).

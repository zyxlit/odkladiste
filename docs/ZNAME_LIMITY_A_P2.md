# Známé limity a backlog P2

## Známé limity verze 1.0

1. **Neaktivní panel a kurzor změny velikosti na hranách:** Protože poličky používají neaktivující `NSPanel` (aby nekradly fokus aktivní aplikaci při přetahování), macOS při najetí na okraj okna ne vždy přepne kurzor na šipku změny velikosti. Změna velikosti funguje jak za okraje, tak přes viditelný úchyt v pravém dolním rohu.
2. **Přesun velkých souborů přes pomalé nebo síťové svazky:** Pokud Finder nestihne dokončit fyzický přesun do ~1,9 s od ukončení drag session, Odkladiště položku neodebere naslepo, ale přepne ji do stavu *„Předání nelze ověřit“* s volbou *Odebrat / Ponechat*.
3. **Explicitní „Kopírovat do složky… / Přesunout do složky…“:** Zatím není jako samostatná položka v kontextovém menu (běžný drag & drop do Finderu fungoval v testech spolehlivě); lze snadno doplnit při potřebě.
4. **Globální změna zkratek v Nastavení:** Záložka Zkratky zobrazuje výchozí zkratky (`⌃⌥N`, `⌃⌥O`) a stav jejich registrace; vlastní přemapování na jiné kombinace je vhodné doplnit v navazující aktualizaci.
5. **Režim bez plného Xcode:** Projekt se sestavuje přes Swift Package Manager (`Package.swift`) a `scripts/build-app.sh`. Pro budoucí distribuci mimo vlastní build bude potřeba Developer ID podpis a notarizace.

---

## Backlog P2 (budoucí rozšíření)

- **Detekce třesení (shake gesture) během tažení:** Vyvolání nové poličky zatřesením kurzorem při držení souboru (s volitelnou citlivostí, cooldownem a možností vypnutí).
- **Příjem prostého textu a webových odkazů (URL):** Uložení výstřižků nebo odkazů přímo na poličku.
- **Příjem slíbených souborů (`NSFilePromiseReceiver`):** Podpora přetahování obsahu z aplikací, které neposkytují existující `fileURL` (např. obrázky přímo z prohlížeče nebo Fotek), s oddělenou správou vlastních dat.
- **Přichycení k hraně obrazovky (edge snapping / auto-collapse):** Magnetické přichycení poličky ke kraji monitoru.
- **Historie odstraněných poliček:** Možnost obnovit nedávno smazanou poličku.
- **Vlastní akce nad soubory:** Např. rychlá komprese do ZIPu nebo spuštění uživatelské akce.

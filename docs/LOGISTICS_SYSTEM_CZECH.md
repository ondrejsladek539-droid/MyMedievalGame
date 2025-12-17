# Implementace Fyzické Logistiky Surovin (RimWorld Style)

Byl implementován systém fyzických surovin, který nahrazuje abstraktní "globální banku" surovin. Suroviny nyní musí být fyzicky přeneseny do skladiště a následně na staveniště.

## Klíčové Změny

### 1. ItemDrop a Fyzická existence
- **Před:** Suroviny zmizely po vytěžení a přičetly se do UI počítadla.
- **Nyní:** Po vytěžení stromu/kamene zůstane na zemi ležet `ItemDrop`.
- **Logika:** `ItemDrop` automaticky vytvoří `HAUL` (přenášecí) job, pokud neleží ve skladišti.

### 2. Skladiště (Stockpile Zones)
- Implementována detekce skladišť v `ZoneManager`.
- Pokud je předmět položen do zóny `STORAGE`, automaticky se zaregistruje do `ResourceManager`.
- Tím se aktualizuje UI počítadlo, které nyní reprezentuje "Suroviny dostupné ve skladištích".

### 3. Hauling (Přenášení)
- Pawni mají novou logiku pro job `HAUL`.
- **Cyklus:**
  1. Jdi k předmětu na zemi.
  2. Seber ho (do inventáře).
  3. Najdi nejbližší skladiště.
  4. Polož předmět na zem (vytvoř nový `ItemDrop` nebo přidej k existujícímu stacku).

### 4. Konstrukce a Doručování
- Stavba (`DELIVER_RESOURCES`) nyní vyžaduje fyzické vyzvednutí suroviny.
- Pawn si vybere nejbližší `ItemDrop` (na zemi nebo ve skladišti).
- Dojde k němu, fyzicky odebere část stacku (`reduce_amount`).
- Odnese surovinu k Blueprintu a vloží ji tam.

## Jak to funguje v kódu

### `Pawn.gd`
- Upravena metoda `_deposit_items`: Místo smazání itemu ho instanciuje do světa.
- Upravena metoda `_handle_resource_pickup`: Používá `reduce_amount` na `ItemDrop`.
- Upravena metoda `_on_job_completed`: Správně řeší sebrání itemu a odregistraci ze skladiště.

### `ItemDrop.gd`
- Přidána kontrola `is_in_stockpile` při startu.
- Metoda `reduce_amount()`: Bezpečně odebere množství a aktualizuje `ResourceManager`.

### `ResourceManager.gd`
- Přidány metody `register_item` a `unregister_item`.
- Nyní funguje spíše jako "účetní kniha" toho, co je ve skladištích, než jako magický sklad.

## Manuální Kroky pro Uživatele (Setup)
1. **Vytvořte Skladiště:** Ve hře musíte pomocí nástroje "Zone" označit oblast jako "Storage", jinak pawni nebudou mít kam nosit věci.
2. **Žádné další kroky:** Vše funguje automaticky s existujícími stromy a kameny.

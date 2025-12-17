# Dokumentace k Data-Driven Systému

Tento dokument popisuje, jak funguje nový JSON systém pro definici herních objektů a jak přidávat nový obsah.

## Přehled
Všechny herní objekty (budovy, nábytek, předměty) jsou nyní definovány v externích JSON souborech ve složce `res://data/`. Hra tyto soubory načte při startu pomocí `DataManager`.

## Soubory
- `buildings.json`: Zdi, podlahy, dveře, okna.
- `furniture.json`: Nábytek (stoly, postele).
- `items.json`: Suroviny a předměty (dřevo, jídlo).
- `pawns.json`: Definice postav (zatím prázdné).

## Jak přidat novou budovu
1. Otevřete `res://data/buildings.json` (nebo `furniture.json`).
2. Přidejte nový záznam do hlavního objektu.

### Příklad: Kamenná zeď
```json
"StoneWall": {
    "name": "Stone Wall",
    "type": "structure",
    "scene_path": "res://scenes/structures/Wall.tscn",
    "texture_path": "res://textures/structures/stone_wall.png",
    "cost": {"Stone": 5},
    "description": "A strong stone wall.",
    "walkable": false
}
```

### Vysvětlení polí:
- **Klíč ("StoneWall")**: Unikátní identifikátor. Používá se v kódu.
- **name**: Název zobrazený hráči v menu.
- **type**: Typ objektu (`structure`, `floor`, `furniture`).
- **scene_path**: Cesta k `.tscn` souboru (lze recyklovat existující scény).
- **texture_path**: (Volitelné) Cesta k obrázku, který přepíše texturu objektu.
- **cost**: Slovník surovin potřebných ke stavbě.
- **walkable**: `true` pokud lze přes objekt chodit (podlahy, dveře), jinak `false`.

## Jak přidat nový předmět
Otevřete `res://data/items.json` a přidejte záznam:

```json
"Iron": {
    "name": "Iron Ingot",
    "category": "Raw Material",
    "stack_size": 100,
    "value": 5.0
}
```

## Důležité
- Po úpravě JSON souborů stačí restartovat hru. Není třeba zasahovat do kódu.
- Pokud přidáte nový klíč budovy, automaticky se objeví v menu "Architect".

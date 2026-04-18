#!/usr/bin/env python3
"""
generate_transmutation_sprites.py
==================================
Génère les sprites de transmutation pour le mod Noita "Random Transmutation".

Les matériaux sont chargés depuis materials.json (à côté du script par défaut).
Les groupes sont chargés depuis groups.lua (à côté du script par défaut).
Les assets visuels (formes + flèche) sont chargés depuis le dossier assets/.

Format de materials.json :
  {
    "water":       { "color": [29, 95, 200],  "type": "liquid" },
    "blood":       { "color": [180, 10, 10],  "type": "liquid" },
    "gunpowder":   { "color": [75, 75, 75],   "type": "powder" },
    ...
  }

Format de groups.lua :
  return {
    ["water"] = {
        representative = "water",
        members        = { "water", "water_fading", ... },
        weight         = 1000,
    },
    ...
  }
  La couleur et le type de chaque groupe sont récupérés depuis materials.json
  en utilisant directement le NOM du groupe (clé Lua) — le champ "representative"
  est ignoré.

Structure des assets (assets/ à côté du script) :
  arrow.png    ← flèche (blanc/gris sur fond transparent)
  liquid.png   solid.png   gas.png   fire.png   powder.png

Chaque asset matériau est teinté avec la couleur du matériau (multiplication),
donc dessinez-les en blanc/gris sur fond transparent.

Layout du sprite généré (taille = taille de arrow.png) :
  ┌───────────────┐
  │ [mat_A teinté]│   coin haut-gauche
  │    [flèche]   │   centrée
  │  [mat_B teinté│   coin bas-droit
  └───────────────┘

Utilisation :
  python generate_transmutation_sprites.py list
  python generate_transmutation_sprites.py single water blood
  python generate_transmutation_sprites.py single water blood -o ./sprites
  python generate_transmutation_sprites.py all -o ./sprites
  python generate_transmutation_sprites.py batch pairs.txt -o ./sprites

  # Fichiers alternatifs :
  python generate_transmutation_sprites.py --materials mon_pool.json --assets ./assets_hd single water blood
  python generate_transmutation_sprites.py --groups mon_groups.lua all-groups -o ./sprites
"""

import argparse
import itertools
import json
import re
import sys
from pathlib import Path
from PIL import Image

# Types reconnus → nom du fichier asset correspondant
TYPE_ASSET: dict[str, str] = {
    "liquid": "liquid.png",
    "powder": "powder.png",
    "solid":  "solid.png",
    "gas":    "gas.png",
    "fire":   "fire.png",
}

ARROW_ASSET = "arrow.png"


# ─── Chargement des matériaux ─────────────────────────────────────────────────

def load_materials(path: Path) -> dict[str, dict]:
    """
    Charge et valide materials.json.

    Format attendu :
      {
        "nom_materiau": { "color": [R, G, B], "type": "liquid|powder|solid|gas|fire" },
        ...
      }

    - Les entrées invalides sont ignorées avec un avertissement.
    - Les types inconnus (pas de fichier asset) émettent un avertissement
      mais ne bloquent pas le chargement ; ils seront signalés lors de la génération.
    """
    if not path.exists():
        print(f"Erreur : fichier matériaux introuvable : {path}", file=sys.stderr)
        print( "  Créez materials.json à côté du script, ou passez --materials <chemin>.",
               file=sys.stderr)
        sys.exit(1)

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"Erreur JSON dans {path} : {e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(raw, dict):
        print(f"Erreur : {path} doit être un objet JSON (dict), pas {type(raw).__name__}.",
              file=sys.stderr)
        sys.exit(1)

    materials: dict[str, dict] = {}
    skipped = 0
    unknown_types: set[str] = set()

    for name, entry in raw.items():
        # Validation de base
        if not isinstance(entry, dict):
            print(f"  ⚠ '{name}' ignoré : valeur attendue dict, reçu {type(entry).__name__}")
            skipped += 1
            continue

        color = entry.get("color")
        mat_type = entry.get("type")

        if (
            not isinstance(color, list)
            or len(color) != 3
            or not all(isinstance(c, int) and 0 <= c <= 255 for c in color)
        ):
            print(f"  ⚠ '{name}' ignoré : 'color' doit être [R, G, B] avec R/G/B ∈ [0, 255]")
            skipped += 1
            continue

        if not isinstance(mat_type, str) or not mat_type:
            print(f"  ⚠ '{name}' ignoré : 'type' manquant ou invalide")
            skipped += 1
            continue

        if mat_type not in TYPE_ASSET:
            unknown_types.add(mat_type)

        materials[name] = {"color": tuple(color), "type": mat_type}

    if unknown_types:
        print(f"  ⚠ Types sans asset défini : {', '.join(sorted(unknown_types))}")
        print(f"    Ces matériaux seront ignorés à la génération (pas de {', '.join(TYPE_ASSET)} correspondant).")

    if skipped:
        print(f"  {skipped} entrée(s) ignorée(s) sur {len(raw)}.")

    print(f"  {len(materials)} matériaux chargés depuis '{path}'.")
    return materials


# ─── Chargement des groupes (groups.lua) ──────────────────────────────────────

def _parse_lua_groups(text: str) -> dict[str, list[str]]:
    """
    Parse le fichier groups.lua et retourne un dict :
      group_name → [member1, member2, ...]

    Ne s'appuie pas sur le champ "representative" — seul le nom de clé Lua
    et la liste "members" sont utilisés.

    L'algorithme suit les accolades pour délimiter chaque bloc de groupe,
    ce qui le rend robuste même si les membres occupent plusieurs lignes.
    """
    result: dict[str, list[str]] = {}

    # Repère chaque ["group_name"] = {
    key_re = re.compile(r'\["(\w+)"\]\s*=\s*\{')

    for m in key_re.finditer(text):
        group_name = m.group(1)
        block_start = m.end()          # position juste après l'accolade ouvrante

        # Avancer jusqu'à l'accolade fermante correspondante (depth tracking)
        depth = 1
        i = block_start
        while i < len(text) and depth > 0:
            ch = text[i]
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
            i += 1
        block_content = text[block_start : i - 1]

        # Extraire members = { "a", "b", ... }
        members_match = re.search(r'members\s*=\s*\{([^}]*)\}', block_content)
        if members_match:
            members = re.findall(r'"(\w+)"', members_match.group(1))
        else:
            members = [group_name]

        result[group_name] = members

    return result


def load_groups(path: Path, materials: dict) -> dict[str, dict]:
    """
    Charge groups.lua et retourne un dict :
      group_name → {"color": ..., "type": ..., "members": [...]}

    La couleur et le type sont ceux du matériau portant le MÊME NOM que le groupe
    dans materials.json (le champ "representative" est ignoré).

    Les groupes dont le nom est absent de materials.json ou dont le type n'a pas
    d'asset défini sont ignorés avec un avertissement.
    """
    if not path.exists():
        print(f"Erreur : groups.lua introuvable : {path}", file=sys.stderr)
        print( "  Vérifiez le chemin ou passez --groups <chemin>.", file=sys.stderr)
        sys.exit(1)

    raw_groups = _parse_lua_groups(path.read_text(encoding="utf-8"))

    groups: dict[str, dict] = {}
    skipped = 0

    for group_name, members in raw_groups.items():
        # Lookup par nom de groupe dans materials.json (pas par representative)
        if group_name not in materials:
            print(f"  ⚠ Groupe '{group_name}' ignoré : absent de materials.json")
            skipped += 1
            continue

        mat = materials[group_name]
        if mat["type"] not in TYPE_ASSET:
            print(f"  ⚠ Groupe '{group_name}' ignoré : type '{mat['type']}' sans asset défini")
            skipped += 1
            continue

        groups[group_name] = {
            "color":   mat["color"],
            "type":    mat["type"],
            "members": members,
        }

    if skipped:
        print(f"  {skipped} groupe(s) ignoré(s).")
    print(f"  {len(groups)} groupes chargés depuis '{path}'.")
    return groups


def groups_to_material_lookup(groups: dict[str, dict]) -> dict[str, str]:
    """
    Retourne un dict material_name → group_name pour le mapping Lua.
    Utile aussi pour vérifier quel groupe sera utilisé pour un matériau donné.
    """
    lookup: dict[str, str] = {}
    for group_name, data in groups.items():
        for member in data["members"]:
            lookup[member] = group_name
    return lookup


# ─── Chargement & cache des assets ───────────────────────────────────────────

_asset_cache: dict[str, Image.Image] = {}

def load_asset(assets_dir: Path, filename: str) -> Image.Image:
    key = str(assets_dir / filename)
    if key not in _asset_cache:
        path = assets_dir / filename
        if not path.exists():
            print(f"\n  ✗ Asset manquant : {path}", file=sys.stderr)
            print(f"    Vérifiez le dossier --assets.", file=sys.stderr)
            sys.exit(1)
        _asset_cache[key] = Image.open(path).convert("RGBA")
    return _asset_cache[key].copy()


def validate_assets(assets_dir: Path, materials: dict) -> None:
    """
    Vérifie que arrow.png est présent et que chaque type utilisé
    dans materials a bien son asset correspondant.
    """
    missing = []

    if not (assets_dir / ARROW_ASSET).exists():
        missing.append(str(assets_dir / ARROW_ASSET))

    used_types = {data["type"] for data in materials.values() if data["type"] in TYPE_ASSET}
    for mat_type in used_types:
        asset_file = TYPE_ASSET[mat_type]
        if not (assets_dir / asset_file).exists():
            missing.append(str(assets_dir / asset_file))

    if missing:
        print("Assets manquants :", file=sys.stderr)
        for m in missing:
            print(f"  ✗ {m}", file=sys.stderr)
        sys.exit(1)


# ─── Teinte ──────────────────────────────────────────────────────────────────

def tint(image: Image.Image, color: tuple[int, int, int]) -> Image.Image:
    """
    Teinte une image RGBA blanc/gris avec la couleur donnée.
    Multiplication canal par canal : canal_out = canal_src × couleur / 255
      → blanc  (255) → couleur exacte
      → gris   (128) → version sombre de la couleur
      → noir   (  0) → reste noir
    L'alpha est préservé intact.
    """
    r, g, b, a = image.split()
    cr, cg, cb = color
    r = r.point(lambda x: x * cr // 255)
    g = g.point(lambda x: x * cg // 255)
    b = b.point(lambda x: x * cb // 255)
    return Image.merge("RGBA", (r, g, b, a))


# ─── Génération d'un sprite ──────────────────────────────────────────────────

def generate_sprite(
    mat_a: str,
    mat_b: str,
    materials: dict,
    assets_dir: Path,
) -> Image.Image:
    """
    Génère un sprite de transmutation mat_A → mat_B.

    La taille du canvas est celle de arrow.png.
    Les formes sont placées pixel-perfect dans les coins.
    """
    for name in (mat_a, mat_b):
        if name not in materials:
            raise ValueError(f"Matériau inconnu : '{name}' — lancez 'list' pour voir les options.")
        if materials[name]["type"] not in TYPE_ASSET:
            raise ValueError(
                f"'{name}' a le type '{materials[name]['type']}' "
                f"qui n'a pas d'asset défini dans TYPE_ASSET."
            )
    if mat_a == mat_b:
        raise ValueError(f"Les deux matériaux sont identiques : '{mat_a}'.")

    data_a = materials[mat_a]
    data_b = materials[mat_b]

    arrow   = load_asset(assets_dir, ARROW_ASSET)
    shape_a = load_asset(assets_dir, TYPE_ASSET[data_a["type"]])
    shape_b = load_asset(assets_dir, TYPE_ASSET[data_b["type"]])

    canvas_w, canvas_h = arrow.size
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))

    # Flèche centrée (couche du bas)
    ax = (canvas_w - arrow.size[0]) // 2
    ay = (canvas_h - arrow.size[1]) // 2
    canvas.paste(arrow, (ax, ay), arrow)

    # mat_A → haut-gauche
    canvas.paste(tint(shape_a, data_a["color"]), (0, 0), shape_a)

    # mat_B → bas-droit
    bx = canvas_w - shape_b.size[0]
    by = canvas_h - shape_b.size[1]
    canvas.paste(tint(shape_b, data_b["color"]), (bx, by), shape_b)

    return canvas


# ─── Batch helpers ───────────────────────────────────────────────────────────

def _run_pairs(
    pairs: list[tuple[str, str]],
    output_dir: Path,
    materials: dict,
    assets_dir: Path,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    ok = 0
    for mat_a, mat_b in pairs:
        try:
            sprite = generate_sprite(mat_a, mat_b, materials, assets_dir)
            fname = output_dir / f"{mat_a}_to_{mat_b}.png"
            sprite.save(fname)
            print(f"  ✓  {fname.name}")
            ok += 1
        except ValueError as e:
            print(f"  ✗  {mat_a} → {mat_b} : {e}")
    print(f"\n{ok}/{len(pairs)} sprites générés dans '{output_dir}'")


def generate_all(output_dir: Path, materials: dict, assets_dir: Path) -> None:
    """Génère les sprites pour toutes les paires de matériaux (sans groupes)."""
    valid = {n: d for n, d in materials.items() if d["type"] in TYPE_ASSET}
    pairs = list(itertools.permutations(valid.keys(), 2))
    _run_pairs(pairs, output_dir, materials, assets_dir)


def generate_all_groups(output_dir: Path, groups: dict, assets_dir: Path) -> None:
    """
    Génère les sprites par groupes : un sprite par paire (group_A, group_B).
    Utilise la couleur/type du nom de groupe dans materials.json.
    Produit aussi material_to_group.json pour le mapping Lua.
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    # Écrire le fichier de mapping pour le Lua
    lookup = groups_to_material_lookup(groups)
    mapping_path = output_dir / "material_to_group.json"
    mapping_path.write_text(json.dumps(lookup, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"  Mapping Lua : {mapping_path}  ({len(lookup)} matériaux → groupes)")

    # Générer les sprites de groupes
    # On réutilise generate_sprite en passant les données de groupes comme si c'étaient des matériaux
    group_as_materials = {
        name: {"color": data["color"], "type": data["type"]}
        for name, data in groups.items()
    }
    pairs = list(itertools.permutations(groups.keys(), 2))
    _run_pairs(pairs, output_dir, group_as_materials, assets_dir)


def generate_batch(
    pairs_file: Path,
    output_dir: Path,
    materials: dict,
    assets_dir: Path,
) -> None:
    """
    Génère depuis un fichier texte (une paire par ligne, espace ou virgule).
    Les lignes vides et commençant par # sont ignorées.
    """
    pairs: list[tuple[str, str]] = []
    with open(pairs_file, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.replace(",", " ").split()
            if len(parts) != 2:
                print(f"  ⚠ Ligne {lineno} ignorée (format invalide) : '{line}'")
                continue
            pairs.append((parts[0], parts[1]))
    _run_pairs(pairs, output_dir, materials, assets_dir)


# ─── CLI ─────────────────────────────────────────────────────────────────────

def _script_dir() -> Path:
    return Path(__file__).parent


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="generate_transmutation_sprites",
        description="Génère les sprites de transmutation (mod Noita Random Transmutation).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--materials", default=None, metavar="FICHIER",
                        help="materials.json (défaut : à côté du script)")
    parser.add_argument("--assets",    default=None, metavar="DIR",
                        help="Dossier assets PNG (défaut : assets/ à côté du script)")
    parser.add_argument("--groups",    default=None, metavar="FICHIER",
                        help="groups.lua pour la génération par groupes (défaut : à côté du script)")

    sub = parser.add_subparsers(dest="cmd", metavar="<commande>")

    sub.add_parser("list",         help="Liste les matériaux chargés")
    sub.add_parser("list-groups",  help="Liste les groupes (depuis groups.lua)")

    p = sub.add_parser("single", help="Génère le sprite pour une paire de matériaux")
    p.add_argument("mat_a", metavar="MAT_A")
    p.add_argument("mat_b", metavar="MAT_B")
    p.add_argument("-o", "--output", default=".", metavar="DIR")

    p = sub.add_parser("all", help="Génère tous les sprites (matériaux individuels, sans groupes)")
    p.add_argument("-o", "--output", default="sprites_out", metavar="DIR")

    p = sub.add_parser("all-groups",
                       help="Génère les sprites par groupes + material_to_group.json pour Lua")
    p.add_argument("-o", "--output", default="sprites_out", metavar="DIR")

    p = sub.add_parser("batch", help="Génère depuis un fichier de paires texte")
    p.add_argument("pairs_file", metavar="FICHIER")
    p.add_argument("-o", "--output", default="sprites_out", metavar="DIR")

    args = parser.parse_args()

    materials_path = Path(args.materials) if args.materials else _script_dir() / "materials.json"
    assets_dir     = Path(args.assets)    if args.assets    else _script_dir() / "assets"
    groups_path    = Path(args.groups)    if args.groups    else _script_dir() / "groups.lua"

    materials = load_materials(materials_path)

    # ── list ──────────────────────────────────────────────────────────────────
    if args.cmd == "list":
        print(f"\n{'NOM':<35} {'TYPE':<8} {'COULEUR (R,G,B)'}")
        print("─" * 62)
        for name, data in sorted(materials.items()):
            r, g, b = data["color"]
            marker = "" if data["type"] in TYPE_ASSET else "  ⚠ type sans asset"
            print(f"  {name:<33} {data['type']:<8} ({r:3},{g:3},{b:3}){marker}")
        print(f"\nTotal : {len(materials)} matériaux")
        return

    # ── list-groups ───────────────────────────────────────────────────────────
    if args.cmd == "list-groups":
        groups = load_groups(groups_path, materials)
        print(f"\n{'GROUPE':<30} {'TYPE':<8} {'MEMBRES':>7}  EXEMPLES")
        print("─" * 72)
        for name, data in sorted(groups.items()):
            members = data["members"]
            sample = ", ".join(m for m in members[:3] if m != name)
            ellipsis = "…" if len(members) > 3 else ""
            print(f"  {name:<28} {data['type']:<8} {len(members):>5}   {sample}{ellipsis}")
        n = len(groups)
        print(f"\n{n} groupes → {n*(n-1):,} sprites")
        return

    if not args.cmd:
        parser.print_help()
        return

    validate_assets(assets_dir, materials)

    # ── single ────────────────────────────────────────────────────────────────
    if args.cmd == "single":
        out = Path(args.output)
        out.mkdir(parents=True, exist_ok=True)
        try:
            sprite = generate_sprite(args.mat_a, args.mat_b, materials, assets_dir)
            fname = out / f"{args.mat_a}_to_{args.mat_b}.png"
            sprite.save(fname)
            print(f"Sprite généré : {fname}")
        except ValueError as e:
            print(f"Erreur : {e}", file=sys.stderr)
            sys.exit(1)

    # ── all ───────────────────────────────────────────────────────────────────
    elif args.cmd == "all":
        generate_all(Path(args.output), materials, assets_dir)

    # ── all-groups ────────────────────────────────────────────────────────────
    elif args.cmd == "all-groups":
        groups = load_groups(groups_path, materials)
        generate_all_groups(Path(args.output), groups, assets_dir)

    # ── batch ─────────────────────────────────────────────────────────────────
    elif args.cmd == "batch":
        generate_batch(Path(args.pairs_file), Path(args.output), materials, assets_dir)


if __name__ == "__main__":
    main()

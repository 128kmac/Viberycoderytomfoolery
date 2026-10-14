"""Static checks for the built pack, mirroring the engine's own rules for
texture sets and Vibrant Visuals files so mistakes surface before Minecraft
silently ignores them."""

from __future__ import annotations

import json
import os
import sys

from PIL import Image

EXT_PRIORITY = ("tga", "png", "jpg", "jpeg")
CHANNELS = {"RGB": 3, "RGBA": 4, "L": 1, "LA": 2, "P": 3}


def _find(folder, name):
    for ext in EXT_PRIORITY:
        p = os.path.join(folder, f"{name}.{ext}")
        if os.path.exists(p):
            return p
    return None


def validate(root):
    problems = []
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    vanilla = json.load(open(os.path.join(here, "vanilla_data", "block_textures.json")))

    # 1. Every JSON parses
    jsons = {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            if f.endswith(".json"):
                p = os.path.join(dp, f)
                try:
                    jsons[os.path.relpath(p, root)] = json.load(open(p))
                except Exception as e:  # noqa: BLE001
                    problems.append(f"{p}: invalid JSON ({e})")

    man = jsons.get("manifest.json", {})
    if "pbr" not in man.get("capabilities", []):
        problems.append("manifest.json lacks the 'pbr' capability")

    # 2. Texture sets
    blocks = os.path.join(root, "textures", "blocks")
    n_sets = 0
    for rel, d in jsons.items():
        if not rel.endswith(".texture_set.json"):
            continue
        n_sets += 1
        folder = os.path.join(root, os.path.dirname(rel))
        ts = d.get("minecraft:texture_set", {})
        if "color" not in ts:
            problems.append(f"{rel}: missing color layer")
            continue
        if "normal" in ts and "heightmap" in ts:
            problems.append(f"{rel}: both normal and heightmap")
        if "metalness_emissive_roughness" in ts and "metalness_emissive_roughness_subsurface" in ts:
            problems.append(f"{rel}: both MER and MERS")
        sizes = {}
        for layer, want in (("color", (3, 4)), ("normal", (3, 4)),
                            ("metalness_emissive_roughness_subsurface", (4,)),
                            ("metalness_emissive_roughness", (3, 4)), ("heightmap", (1,))):
            ref = ts.get(layer)
            if ref is None or not isinstance(ref, str):
                continue
            p = _find(folder, ref)
            if p is None:
                problems.append(f"{rel}: {layer} '{ref}' not found in the same folder")
                continue
            im = Image.open(p)
            ch = CHANNELS.get(im.mode, 0)
            if ch not in want:
                problems.append(f"{rel}: {layer} has {ch} channels ({im.mode}), needs {want}")
            sizes[layer] = im.size
        if len(set(sizes.values())) > 1:
            problems.append(f"{rel}: layer sizes differ {sizes}")
        tex_rel = os.path.relpath(os.path.join(folder, ts["color"]), blocks).replace(os.sep, "/")
        if tex_rel not in vanilla:
            problems.append(f"{rel}: '{tex_rel}' does not replace any vanilla block texture")
        else:
            for ext in vanilla[tex_rel]:
                if not os.path.exists(os.path.join(folder, f"{ts['color']}.{ext}")):
                    problems.append(f"{rel}: vanilla ships .{ext} for {tex_rel}; pack lacks it (would be shadowed)")
        c = sizes.get("color")
        if c and c[1] % c[0] != 0:
            problems.append(f"{rel}: flipbook height {c[1]} not a multiple of width {c[0]}")
    if n_sets == 0:
        problems.append("no texture sets were generated")

    # 3. Vibrant Visuals identifiers referenced by biomes exist
    defined = {}
    kinds = {
        "minecraft:atmosphere_settings": "atmosphere", "minecraft:lighting_settings": "lighting",
        "minecraft:color_grading_settings": "color_grading", "minecraft:water_settings": "water",
        "minecraft:fog_settings": "fog",
    }
    for rel, d in jsons.items():
        for k, kind in kinds.items():
            if k in d:
                ident = d[k].get("description", {}).get("identifier")
                if not ident or ":" not in ident:
                    problems.append(f"{rel}: missing namespaced identifier")
                if ident in defined.get(kind, {}):
                    problems.append(f"{rel}: duplicate identifier {ident}")
                defined.setdefault(kind, {})[ident] = rel
    refs = {
        "minecraft:atmosphere_identifier": ("atmosphere", "atmosphere_identifier"),
        "minecraft:lighting_identifier": ("lighting", "lighting_identifier"),
        "minecraft:color_grading_identifier": ("color_grading", "color_grading_identifier"),
        "minecraft:water_identifier": ("water", "water_identifier"),
        "minecraft:fog_appearance": ("fog", "fog_identifier"),
    }
    n_biomes = 0
    for rel, d in jsons.items():
        if not rel.endswith(".client_biome.json"):
            continue
        n_biomes += 1
        comp = d["minecraft:client_biome"]["components"]
        for comp_key, (kind, field) in refs.items():
            ident = comp.get(comp_key, {}).get(field)
            if ident is None:
                problems.append(f"{rel}: no {comp_key}")
            elif ident not in defined.get(kind, {}):
                problems.append(f"{rel}: {comp_key} -> {ident} is not defined in the pack")

    # 4. Settings that the engine cannot blend must agree across files
    def same(kind_key, extract, label):
        vals = {}
        for rel, d in jsons.items():
            if kind_key in d:
                vals[rel] = json.dumps(extract(d[kind_key]), sort_keys=True)
        if len(set(vals.values())) > 1:
            problems.append(f"{label} differs between files: {sorted(set(vals.values()))[:3]}")

    same("minecraft:water_settings", lambda s: s.get("caustics"), "water caustics")
    same("minecraft:water_settings", lambda s: s.get("waves", {}).get("enabled"), "water waves.enabled")
    same("minecraft:color_grading_settings", lambda s: s.get("tone_mapping"), "tone mapping operator")
    same("minecraft:lighting_settings",
         lambda s: s.get("directional_lights", {}).get("orbital", {}).get("orbital_offset_degrees"),
         "orbital_offset_degrees")

    # 5. Caustics texture exists and is declared
    tl = jsons.get(os.path.join("textures", "texture_list.json"), [])
    for rel, d in jsons.items():
        if "minecraft:water_settings" in d:
            tex = d["minecraft:water_settings"].get("caustics", {}).get("texture")
            if tex:
                if tex not in tl:
                    problems.append(f"{rel}: caustics texture {tex} not in texture_list.json")
                p = _find(os.path.join(root, os.path.dirname(tex)), os.path.basename(tex))
                if not p:
                    problems.append(f"{rel}: caustics texture {tex} missing")
                else:
                    w, h = Image.open(p).size
                    if h % w:
                        problems.append(f"caustics sheet {w}x{h}: frames must be square")
    if n_biomes == 0:
        problems.append("no client biomes generated")
    return problems


if __name__ == "__main__":
    probs = validate(sys.argv[1])
    print("\n".join(probs) if probs else "ok")
    sys.exit(1 if probs else 0)

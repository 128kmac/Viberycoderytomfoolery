"""Vibrant Visuals configuration: sky, sun/moon, color grading, water, fog,
shadows, local lights and PBR fallbacks, plus the biome rewiring.

Time-of-day keys follow Mojang's convention: 0.0 = noon, 0.25 = sunset,
0.5 = midnight, 0.75 = sunrise, 1.0 = noon again. Most curves here are
authored for the afternoon/evening half and mirrored onto the morning.
"""

from __future__ import annotations

import copy
import json
import os

NS = "halcyon"

# --------------------------------------------------------------------------
# Keyframe helpers
# --------------------------------------------------------------------------


def mirror(half: dict) -> dict:
    """Mirror keys defined on [0, 0.5] onto (0.5, 1]: t -> 1 - t."""
    out = dict(half)
    for t, v in half.items():
        if 0.0 < t < 0.5:
            out[round(1.0 - t, 5)] = v
    out[1.0] = half[0.0]
    return out


def kf(d: dict) -> dict:
    return {f"{t:.4f}": (round(v, 5) if isinstance(v, float) else v) for t, v in sorted(d.items())}


def tint(col, toward, w):
    return [int(round(c * (1 - w) + t * w)) for c, t in zip(col, toward)]


def scale(col, s):
    return [int(max(0, min(255, round(c * s)))) for c in col]


def map_kf(d, fn):
    return {t: fn(v) for t, v in d.items()}


# --------------------------------------------------------------------------
# Base (temperate) curves
# --------------------------------------------------------------------------

SUN_ILLUM = mirror({0.0: 112.0, 0.12: 104.0, 0.18: 80.0, 0.215: 48.0, 0.24: 18.0, 0.255: 6.0,
                    0.27: 1.6, 0.282: 0.35, 0.29: 0.02, 0.292: 0.0, 0.5: 0.0})
SUN_COLOR = mirror({0.0: [255, 247, 236], 0.12: [255, 242, 224], 0.18: [255, 222, 182],
                    0.215: [255, 192, 132], 0.24: [255, 150, 82], 0.258: [255, 118, 58],
                    0.275: [236, 92, 62], 0.29: [196, 84, 92], 0.5: [196, 84, 92]})
MOON_ILLUM = mirror({0.0: 0.0, 0.215: 0.0, 0.245: 0.08, 0.27: 0.3, 0.31: 0.52, 0.5: 0.6})
MOON_COLOR = mirror({0.0: [150, 172, 255], 0.3: [150, 172, 255], 0.5: [160, 182, 255]})
AMBIENT_ILLUM = mirror({0.0: 0.035, 0.22: 0.035, 0.28: 0.045, 0.5: 0.05})
AMBIENT_COLOR = mirror({0.0: [255, 255, 255], 0.22: [255, 244, 232], 0.3: [206, 214, 255], 0.5: [196, 206, 255]})
SKY_INTENSITY = mirror({0.0: 0.92, 0.2: 0.9, 0.25: 0.82, 0.3: 0.62, 0.5: 0.55})

ZENITH = mirror({0.0: [62, 118, 212], 0.15: [70, 122, 206], 0.21: [82, 118, 186], 0.25: [72, 92, 152],
                 0.275: [52, 62, 118], 0.3: [30, 36, 78], 0.35: [12, 16, 40], 0.5: [7, 10, 28]})
HORIZON = mirror({0.0: [176, 206, 240], 0.15: [196, 210, 226], 0.195: [236, 214, 184], 0.225: [255, 186, 132],
                  0.25: [255, 146, 96], 0.265: [236, 112, 104], 0.285: [172, 96, 140], 0.31: [96, 86, 150],
                  0.36: [36, 46, 92], 0.5: [22, 28, 58]})
RAYLEIGH = mirror({0.0: 9.0, 0.18: 8.5, 0.25: 6.5, 0.3: 5.0, 0.5: 4.0})
SUN_MIE = mirror({0.0: 0.22, 0.16: 0.3, 0.21: 0.55, 0.25: 1.1, 0.27: 0.9, 0.29: 0.3, 0.32: 0.0, 0.5: 0.0})
MOON_MIE = mirror({0.0: 0.0, 0.26: 0.0, 0.31: 0.25, 0.5: 0.4})
GLARE = mirror({0.0: 0.035, 0.18: 0.05, 0.25: 0.085, 0.3: 0.04, 0.5: 0.02})
BLEND_START = mirror({0.0: 0.8, 0.2: 0.6, 0.25: 0.5, 0.3: 0.25, 0.5: 0.3})
BLEND_MIE = mirror({0.0: 0.5, 0.1: 0.5, 0.2: 1.0, 0.25: 0.9, 0.3: 0.5, 0.5: 0.5})

ORBITAL_OFFSET = 18.0  # tilt the sun's path so shadows rake across the world


# --------------------------------------------------------------------------
# Profiles
# --------------------------------------------------------------------------
# Each profile tweaks the base curves. Keys:
#   sun_tint (rgb, weight), sun_scale, zenith/horizon (rgb, weight), rayleigh, mie,
#   ambient_scale, ambient_tint, sky, grade{...}, fog{...}

PROFILES = {
    "default": {},
    "meadow": dict(sun_tint=([255, 240, 214], 0.15), horizon=([236, 226, 196], 0.08),
                   grade=dict(temperature=6200, saturation=1.08)),
    "warm": dict(sun_tint=([255, 214, 150], 0.25), zenith=([150, 176, 206], 0.25), horizon=([238, 214, 172], 0.3),
                 rayleigh=0.85, mie=1.35, grade=dict(temperature=5400, saturation=1.06, contrast=1.08),
                 fog=dict(density=0.07, scattering=[0.05, 0.045, 0.035], g=0.75, top=230)),
    "mesa": dict(sun_tint=([255, 196, 140], 0.3), zenith=([150, 170, 206], 0.2), horizon=([240, 196, 156], 0.35),
                 rayleigh=0.85, mie=1.3, grade=dict(temperature=5000, saturation=1.12, contrast=1.08),
                 fog=dict(density=0.06, scattering=[0.055, 0.042, 0.032], g=0.72, top=230)),
    "savanna": dict(sun_tint=([255, 222, 160], 0.22), horizon=([236, 214, 170], 0.25), mie=1.2,
                    grade=dict(temperature=5600, saturation=1.05),
                    fog=dict(density=0.06, scattering=[0.048, 0.044, 0.036], g=0.72)),
    "cold": dict(sun_tint=([226, 236, 255], 0.2), zenith=([80, 130, 210], 0.15), horizon=([214, 228, 246], 0.25),
                 rayleigh=1.1, ambient_tint=([214, 226, 255], 0.3),
                 grade=dict(temperature=7400, saturation=0.96, contrast=1.06),
                 fog=dict(density=0.05, scattering=[0.04, 0.045, 0.055], g=0.6)),
    "taiga": dict(sun_tint=([240, 240, 255], 0.1), horizon=([206, 214, 226], 0.15),
                  grade=dict(temperature=6900, saturation=0.98),
                  fog=dict(density=0.08, scattering=[0.04, 0.045, 0.05], g=0.65, top=200)),
    "swamp": dict(sun_tint=([220, 230, 180], 0.25), sun_scale=0.8, zenith=([110, 130, 120], 0.35),
                  horizon=([170, 180, 150], 0.4), rayleigh=0.8, mie=1.2, sky=0.85,
                  grade=dict(temperature=6000, saturation=0.88, contrast=1.04, tint=[1.0, 1.02, 0.95]),
                  fog=dict(density=0.16, scattering=[0.05, 0.055, 0.045], absorption=[0.01, 0.006, 0.012], g=0.55,
                           top=140)),
    "mangrove": dict(sun_tint=([236, 220, 170], 0.25), sun_scale=0.85, zenith=([110, 136, 130], 0.3),
                     horizon=([186, 186, 150], 0.35), mie=1.25, sky=0.85,
                     grade=dict(temperature=5800, saturation=0.92, contrast=1.04),
                     fog=dict(density=0.14, scattering=[0.052, 0.05, 0.04], absorption=[0.008, 0.008, 0.014], g=0.55,
                              top=140)),
    "jungle": dict(sun_tint=([255, 236, 196], 0.15), horizon=([206, 222, 206], 0.2), mie=1.25,
                   grade=dict(temperature=6100, saturation=1.12, contrast=1.06),
                   fog=dict(density=0.12, scattering=[0.045, 0.05, 0.045], g=0.68, top=170)),
    "dark_forest": dict(sun_scale=0.85, horizon=([186, 196, 190], 0.2), sky=0.8,
                        grade=dict(temperature=6300, saturation=0.92, contrast=1.08),
                        fog=dict(density=0.12, scattering=[0.04, 0.045, 0.045], g=0.6, top=150)),
    "pale": dict(sun_tint=([230, 230, 230], 0.5), sun_scale=0.8, zenith=([150, 156, 164], 0.6),
                 horizon=([196, 196, 196], 0.6), rayleigh=0.7, sky=0.8,
                 grade=dict(temperature=6800, saturation=0.62, contrast=1.06),
                 fog=dict(density=0.2, scattering=[0.06, 0.06, 0.062], g=0.45, top=170)),
    "cherry": dict(sun_tint=([255, 226, 226], 0.18), horizon=([246, 214, 226], 0.22),
                   grade=dict(temperature=6300, saturation=1.08, tint=[1.02, 0.99, 1.01]),
                   fog=dict(density=0.07, scattering=[0.05, 0.044, 0.048], g=0.7)),
    "mushroom": dict(sun_tint=([246, 214, 246], 0.18), zenith=([110, 110, 200], 0.2), horizon=([222, 196, 236], 0.3),
                     grade=dict(temperature=6800, saturation=1.1, tint=[1.02, 0.97, 1.03]),
                     fog=dict(density=0.08, scattering=[0.05, 0.042, 0.055], g=0.6)),
    "ocean": dict(zenith=([50, 110, 214], 0.15), horizon=([176, 210, 246], 0.15), rayleigh=1.05,
                  grade=dict(temperature=6700, saturation=1.06),
                  fog=dict(density=0.05, scattering=[0.038, 0.045, 0.055], g=0.72, top=200)),
    "mountain": dict(rayleigh=1.15, zenith=([44, 100, 206], 0.2), grade=dict(temperature=6800, contrast=1.08),
                     fog=dict(density=0.05, scattering=[0.036, 0.042, 0.052], g=0.72, bottom=100, top=260)),
    # Underground biomes (applied while the camera is inside them)
    "lush_caves": dict(ambient_scale=2.0, ambient_tint=([200, 255, 210], 0.3),
                       grade=dict(temperature=6200, saturation=1.12),
                       fog=dict(density=0.1, scattering=[0.04, 0.05, 0.04], g=0.5, uniform=True)),
    "dripstone": dict(ambient_scale=1.4, ambient_tint=([255, 226, 196], 0.2), grade=dict(temperature=5900),
                      fog=dict(density=0.08, scattering=[0.045, 0.04, 0.035], g=0.5, uniform=True)),
    "deep_dark": dict(ambient_scale=0.6, ambient_tint=([150, 196, 220], 0.5), sky=0.6,
                      grade=dict(temperature=8200, saturation=0.82, contrast=1.12),
                      fog=dict(density=0.14, scattering=[0.03, 0.04, 0.05], g=0.4, uniform=True)),
    "sulfur": dict(ambient_scale=1.5, ambient_tint=([255, 240, 170], 0.35), grade=dict(temperature=5600, saturation=1.05),
                   fog=dict(density=0.12, scattering=[0.05, 0.05, 0.03], absorption=[0.004, 0.004, 0.012], g=0.5,
                            uniform=True)),
}

NETHER = {
    "hell": dict(zenith=[64, 14, 10], horizon=[96, 24, 16], ambient=([255, 170, 140], 0.55),
                 grade=dict(temperature=5200, saturation=1.08, contrast=1.06),
                 fog=dict(density=0.18, scattering=[0.12, 0.05, 0.035], absorption=[0.02, 0.05, 0.06], g=0.35)),
    "crimson": dict(zenith=[70, 10, 14], horizon=[120, 22, 24], ambient=([255, 150, 150], 0.55),
                    grade=dict(temperature=5400, saturation=1.12, contrast=1.06),
                    fog=dict(density=0.2, scattering=[0.14, 0.04, 0.04], absorption=[0.02, 0.06, 0.05], g=0.4)),
    "warped": dict(zenith=[14, 40, 42], horizon=[28, 74, 70], ambient=([170, 255, 236], 0.5),
                   grade=dict(temperature=7200, saturation=1.1, contrast=1.06),
                   fog=dict(density=0.18, scattering=[0.035, 0.09, 0.085], absorption=[0.05, 0.02, 0.02], g=0.4)),
    "soul": dict(zenith=[26, 40, 48], horizon=[50, 70, 78], ambient=([176, 236, 255], 0.55),
                 grade=dict(temperature=7600, saturation=0.9, contrast=1.08),
                 fog=dict(density=0.22, scattering=[0.05, 0.08, 0.09], absorption=[0.03, 0.02, 0.015], g=0.3)),
    "basalt": dict(zenith=[52, 46, 50], horizon=[96, 86, 90], ambient=([236, 220, 226], 0.5),
                   grade=dict(temperature=6200, saturation=0.86, contrast=1.08),
                   fog=dict(density=0.28, scattering=[0.09, 0.085, 0.09], absorption=[0.02, 0.02, 0.02], g=0.3)),
}


def biome_profile(name: str) -> str:
    if name in ("hell",):
        return "nether:hell"
    if name == "crimson_forest":
        return "nether:crimson"
    if name == "warped_forest":
        return "nether:warped"
    if name == "soulsand_valley":
        return "nether:soul"
    if name == "basalt_deltas":
        return "nether:basalt"
    if name == "the_end":
        return "end"
    # Order matters: substrings are tested top-down ("mangrove_swamp" and
    # "cherry_grove" both contain "grove").
    table = [
        ("mangrove", "mangrove"), ("swampland", "swamp"), ("cherry", "cherry"),
        ("mesa", "mesa"), ("desert", "warm"), ("savanna", "savanna"),
        ("ice", "cold"), ("frozen", "cold"), ("cold_", "cold"), ("snowy", "cold"), ("grove", "cold"),
        ("jagged_peaks", "cold"), ("legacy_frozen", "cold"),
        ("stony_peaks", "mountain"), ("extreme_hills", "mountain"),
        ("bamboo_jungle", "jungle"), ("jungle", "jungle"),
        ("roofed_forest", "dark_forest"), ("pale_garden", "pale"),
        ("mushroom", "mushroom"), ("taiga", "taiga"),
        ("lush_caves", "lush_caves"), ("dripstone", "dripstone"), ("deep_dark", "deep_dark"),
        ("sulfur", "sulfur"), ("meadow", "meadow"), ("flower_forest", "meadow"), ("sunflower", "meadow"),
        ("ocean", "ocean"), ("beach", "ocean"),
    ]
    for key, prof in table:
        if key in name:
            return prof
    return "default"


def biome_water(name: str) -> str:
    table = [
        ("lukewarm", "lukewarm"), ("warm_ocean", "tropical"),
        ("frozen", "frozen"), ("cold_ocean", "cold"), ("deep_ocean", "deep"), ("ocean", "ocean"),
        ("mangrove", "mangrove"), ("swampland", "swamp"), ("river", "river"), ("jungle", "jungle"),
        ("lush_caves", "lush"), ("beach", "ocean"), ("mushroom", "ocean"), ("desert", "oasis"), ("mesa", "river"),
        ("pale_garden", "pale"), ("dripstone", "cave"), ("deep_dark", "cave"), ("sulfur", "sulfur"),
    ]
    for key, w in table:
        if key in name:
            return w
    return "lake"


# --------------------------------------------------------------------------
# JSON builders
# --------------------------------------------------------------------------

def atmosphere_json(pid, p):
    zen = ZENITH
    hor = HORIZON
    if "zenith" in p:
        c, w = p["zenith"]
        zen = map_kf(ZENITH, lambda v: tint(v, c, w))
    if "horizon" in p:
        c, w = p["horizon"]
        hor = map_kf(HORIZON, lambda v: tint(v, c, w))
    ray = map_kf(RAYLEIGH, lambda v: v * p.get("rayleigh", 1.0))
    mie = map_kf(SUN_MIE, lambda v: v * p.get("mie", 1.0))
    return {
        "format_version": "1.21.40",
        "minecraft:atmosphere_settings": {
            "description": {"identifier": f"{NS}:{pid}_atmospherics"},
            "horizon_blend_stops": {
                "min": kf({0.0: 0.0, 1.0: 0.0}),
                "start": kf(BLEND_START),
                "mie_start": kf(BLEND_MIE),
                "max": kf({0.0: 0.25, 1.0: 0.25}),
            },
            "rayleigh_strength": kf(ray),
            "sun_mie_strength": kf(mie),
            "moon_mie_strength": kf(MOON_MIE),
            "sun_glare_shape": kf(GLARE),
            "sky_zenith_color": kf(zen),
            "sky_horizon_color": kf(hor),
        },
    }


def lighting_json(pid, p, *, dimension="overworld"):
    sun_c = SUN_COLOR
    if "sun_tint" in p:
        c, w = p["sun_tint"]
        # Keep sunsets fiery: blend the tint in mostly during the day.
        sun_c = {t: tint(v, c, w * (1.0 if (t < 0.2 or t > 0.8) else 0.4)) for t, v in SUN_COLOR.items()}
    sun_i = map_kf(SUN_ILLUM, lambda v: v * p.get("sun_scale", 1.0))
    amb_i = map_kf(AMBIENT_ILLUM, lambda v: v * p.get("ambient_scale", 1.0))
    amb_c = AMBIENT_COLOR
    if "ambient_tint" in p:
        c, w = p["ambient_tint"]
        amb_c = map_kf(AMBIENT_COLOR, lambda v: tint(v, c, w))
    sky = map_kf(SKY_INTENSITY, lambda v: max(0.1, min(1.0, v * p.get("sky", 1.0))))
    return {
        "format_version": "1.26.0",
        "minecraft:lighting_settings": {
            "description": {"identifier": f"{NS}:{pid}_lighting"},
            "directional_lights": {
                "orbital": {
                    "sun": {"illuminance": kf(sun_i), "color": kf(sun_c)},
                    "moon": {"illuminance": kf(MOON_ILLUM), "color": kf(MOON_COLOR)},
                    "orbital_offset_degrees": ORBITAL_OFFSET,
                },
                "flash": {"illuminance": 8.0, "color": [214, 120, 255]},
            },
            "emissive": {"desaturation": 0.08},
            "ambient": {"illuminance": kf(amb_i), "color": kf(amb_c)},
            "sky": {"intensity": kf(sky)},
        },
    }


def flat_lighting_json(pid, sun_ill, sun_col, amb_ill, amb_col, flash=None, sky=1.0):
    """Nether/End: no day cycle, so every curve is constant."""
    flat = {0.0: None, 1.0: None}
    return {
        "format_version": "1.26.0",
        "minecraft:lighting_settings": {
            "description": {"identifier": f"{NS}:{pid}_lighting"},
            "directional_lights": {
                "orbital": {
                    "sun": {"illuminance": kf({t: sun_ill for t in flat}), "color": kf({t: sun_col for t in flat})},
                    "moon": {"illuminance": kf({t: sun_ill for t in flat}), "color": kf({t: sun_col for t in flat})},
                    "orbital_offset_degrees": ORBITAL_OFFSET,
                },
                "flash": flash or {"illuminance": 8.0, "color": [214, 120, 255]},
            },
            "emissive": {"desaturation": 0.05},
            "ambient": {"illuminance": amb_ill, "color": amb_col},
            "sky": {"intensity": sky},
        },
    }


def grading_json(pid, g):
    contrast = g.get("contrast", 1.05)
    sat = g.get("saturation", 1.04)
    t = g.get("tint", [1.0, 1.0, 1.0])
    return {
        "format_version": "1.21.90",
        "minecraft:color_grading_settings": {
            "description": {"identifier": f"{NS}:{pid}_color_grading"},
            "color_grading": {
                "midtones": {
                    "contrast": [contrast] * 3,
                    "gain": [round(v, 4) for v in t],
                    "gamma": [2.2, 2.2, 2.2],
                    "offset": [0.0, 0.0, 0.0],
                    "saturation": [sat] * 3,
                },
                # Gentle split-toning: warm highlights, cool lifted shadows.
                "highlights": {
                    "enabled": True,
                    "highlightsMin": 1.6,
                    "contrast": [1.0, 1.0, 1.0],
                    "gain": [1.03, 1.0, 0.965],
                    "gamma": [2.2, 2.2, 2.2],
                    "offset": [0.0, 0.0, 0.0],
                    "saturation": [round(sat * 0.94, 3)] * 3,
                },
                "shadows": {
                    "enabled": True,
                    "shadowsMax": 0.55,
                    "contrast": [round(contrast * 1.02, 3)] * 3,
                    "gain": [0.97, 0.99, 1.04],
                    "gamma": [2.2, 2.2, 2.2],
                    "offset": [0.0, 0.0, 0.003],
                    "saturation": [round(sat * 0.96, 3)] * 3,
                },
                "temperature": {
                    "enabled": True,
                    "temperature": g.get("temperature", 6500),
                    "type": "white_balance",
                },
            },
            # Every grading file must share one operator (it cannot be blended).
            "tone_mapping": {"operator": "aces"},
        },
    }


# Water: particle concentrations (mg/L) set the colour by physically-based
# absorption. Waves and caustics must match across all files.
WAVES = {
    "enabled": True,
    "depth": 0.85,
    "direction_increment": 77.0,
    "frequency": 1.15,
    "frequency_scaling": 1.18,
    "mix": 0.24,
    "octaves": 26,
    "pull": 0.34,
    "sampleWidth": 0.6,
    "shape": 1.7,
    "speed": 1.6,
    "speed_scaling": 1.04,
}
CAUSTICS = {
    "enabled": True,
    "frame_length": 0.06,
    "power": 3,
    "scale": 0.55,
    "texture": "textures/environment/halcyon_caustics",
}
WATERS = {
    "lake": dict(chlorophyll=0.35, suspended_sediment=0.6, cdom=0.5, tint=0.18),
    "river": dict(chlorophyll=0.6, suspended_sediment=3.0, cdom=1.4, tint=0.2),
    "ocean": dict(chlorophyll=0.12, suspended_sediment=0.15, cdom=0.05, tint=0.22),
    "deep": dict(chlorophyll=0.06, suspended_sediment=0.05, cdom=0.02, tint=0.25),
    "tropical": dict(chlorophyll=0.02, suspended_sediment=0.08, cdom=0.0, tint=0.3),
    "lukewarm": dict(chlorophyll=0.12, suspended_sediment=0.1, cdom=0.02, tint=0.25),
    "cold": dict(chlorophyll=0.5, suspended_sediment=0.3, cdom=0.2, tint=0.2),
    "frozen": dict(chlorophyll=0.25, suspended_sediment=0.2, cdom=0.1, tint=0.22),
    "swamp": dict(chlorophyll=4.5, suspended_sediment=12.0, cdom=4.5, tint=0.35),
    "mangrove": dict(chlorophyll=2.5, suspended_sediment=22.0, cdom=6.0, tint=0.35),
    "jungle": dict(chlorophyll=1.6, suspended_sediment=2.0, cdom=1.6, tint=0.22),
    "oasis": dict(chlorophyll=0.15, suspended_sediment=0.4, cdom=0.1, tint=0.3),
    "lush": dict(chlorophyll=1.2, suspended_sediment=0.3, cdom=0.3, tint=0.25),
    "pale": dict(chlorophyll=0.4, suspended_sediment=4.0, cdom=2.0, tint=0.15),
    "cave": dict(chlorophyll=0.05, suspended_sediment=0.8, cdom=0.2, tint=0.12),
    "sulfur": dict(chlorophyll=0.4, suspended_sediment=6.0, cdom=3.0, tint=0.2),
}


def water_json(wid, w):
    return {
        "format_version": "1.26.0",
        "minecraft:water_settings": {
            "description": {"identifier": f"{NS}:{wid}_water"},
            "particle_concentrations": {
                "chlorophyll": w["chlorophyll"],
                "suspended_sediment": w["suspended_sediment"],
                "cdom": w["cdom"],
            },
            "waves": dict(WAVES),
            "caustics": dict(CAUSTICS),
            "biome_water_color_contribution": w["tint"],
        },
    }


WATER_FOG = {
    # Underwater volumetrics: absorption is applied as luminance in VV, so the
    # hue comes from the water settings; this mainly sets visibility and shafts.
    "default": dict(density=0.32, scattering=[0.018, 0.022, 0.028], absorption=[0.2, 0.08, 0.08], g=0.62),
    "murky": dict(density=0.6, scattering=[0.04, 0.045, 0.03], absorption=[0.3, 0.2, 0.25], g=0.5),
    "clear": dict(density=0.22, scattering=[0.012, 0.018, 0.024], absorption=[0.16, 0.06, 0.06], g=0.66),
}


def volumetric(f, water_kind="default"):
    f = dict(f or {})
    dens = f.get("density", 0.06)
    air = {"max_density": dens}
    if f.get("uniform"):
        air["uniform"] = True
    else:
        air["max_density_height"] = float(f.get("bottom", 64))
        air["zero_density_height"] = float(f.get("top", 210))
    wf = WATER_FOG[water_kind]
    return {
        "density": {
            "air": air,
            "weather": {"max_density": min(0.5, dens * 2.6 + 0.05),
                        "max_density_height": 64.0, "zero_density_height": 260.0},
            "water": {"max_density": wf["density"], "uniform": True},
        },
        "media_coefficients": {
            "air": {"scattering": f.get("scattering", [0.04, 0.044, 0.05]),
                    "absorption": f.get("absorption", [0.0, 0.0, 0.0])},
            "water": {"scattering": wf["scattering"], "absorption": wf["absorption"]},
        },
        "henyey_greenstein_g": {
            "air": {"henyey_greenstein_g": f.get("g", 0.7)},
            "water": {"henyey_greenstein_g": wf["g"]},
        },
    }


DEFAULT_FOG = dict(density=0.06, scattering=[0.04, 0.044, 0.05], g=0.7)

# --------------------------------------------------------------------------
# Local lights (block light colours). Point lights cast real dynamic shadows.
# --------------------------------------------------------------------------

POINT = {
    "minecraft:torch": "#FFC27A",
    "minecraft:lantern": "#FFB262",
    "minecraft:soul_torch": "#62E4FF",
    "minecraft:soul_lantern": "#62E4FF",
    "minecraft:redstone_torch": "#FF3A1C",
    "minecraft:end_rod": "#F2E6FF",
    "minecraft:sea_pickle": "#9CFFE2",
    "minecraft:copper_torch": "#A6F2A0",
    "minecraft:copper_lantern": "#A6F2A0",
    "minecraft:exposed_copper_lantern": "#A6F2A0",
    "minecraft:weathered_copper_lantern": "#A6F2A0",
    "minecraft:oxidized_copper_lantern": "#A6F2A0",
    "minecraft:waxed_copper_lantern": "#A6F2A0",
    "minecraft:waxed_exposed_copper_lantern": "#A6F2A0",
    "minecraft:waxed_weathered_copper_lantern": "#A6F2A0",
    "minecraft:waxed_oxidized_copper_lantern": "#A6F2A0",
    "minecraft:candle": "#FFB46A",
    "minecraft:candle_cake": "#FFB46A",
}
for _c in ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "light_gray",
           "cyan", "purple", "blue", "brown", "green", "red", "black"]:
    POINT[f"minecraft:{_c}_candle"] = "#FFB46A"
    POINT[f"minecraft:{_c}_candle_cake"] = "#FFB46A"

STATIC = {
    "minecraft:glowstone": "#FFD08A",
    "minecraft:sea_lantern": "#C2F4FF",
    "minecraft:shroomlight": "#FFA458",
    "minecraft:lava": "#FF7A24",
    "minecraft:flowing_lava": "#FF7A24",
    "minecraft:magma": "#FF5A1C",
    "minecraft:fire": "#FF9A3A",
    "minecraft:soul_fire": "#62E4FF",
    "minecraft:campfire": "#FFA046",
    "minecraft:soul_campfire": "#62E4FF",
    "minecraft:lit_pumpkin": "#FFB04C",
    "minecraft:lit_redstone_lamp": "#FFB872",
    "minecraft:beacon": "#E6FFFF",
    "minecraft:conduit": "#80E6FF",
    "minecraft:ochre_froglight": "#FFE7A0",
    "minecraft:verdant_froglight": "#CCFFBC",
    "minecraft:pearlescent_froglight": "#FFD8F2",
    "minecraft:crying_obsidian": "#A444FF",
    "minecraft:respawn_anchor": "#C462FF",
    "minecraft:portal": "#B044FF",
    "minecraft:glow_lichen": "#A4F2C6",
    "minecraft:amethyst_cluster": "#D8AAFF",
    "minecraft:lit_furnace": "#FF9440",
    "minecraft:lit_blast_furnace": "#FF9440",
    "minecraft:lit_smoker": "#FF9440",
    "minecraft:lit_redstone_ore": "#FF3220",
    "minecraft:lit_deepslate_redstone_ore": "#FF3220",
    "minecraft:enchanting_table": "#B48CFF",
    "minecraft:end_portal_frame": "#9CF0D0",
    "minecraft:brewing_stand": "#FFD680",
    "minecraft:copper_bulb": "#FFD9A0",
}


def local_lighting_json():
    entries = {}
    for k, v in POINT.items():
        entries[k] = {"light_color": v, "light_type": "point_light"}
    for k, v in STATIC.items():
        entries[k] = {"light_color": v, "light_type": "static_light"}
    return {"format_version": "1.21.120", "minecraft:local_light_settings": entries}


def pbr_json():
    return {
        "format_version": "1.21.40",
        "minecraft:pbr_fallback_settings": {
            "blocks": {"global_metalness_emissive_roughness_subsurface": [0, 0, 225, 0]},
            "actors": {"global_metalness_emissive_roughness_subsurface": [0, 0, 205, 40]},
            "particles": {"global_metalness_emissive_roughness_subsurface": [0, 0, 255, 0]},
            "items": {"global_metalness_emissive_roughness_subsurface": [0, 0, 200, 0]},
        },
    }


def shadows_json():
    return {"format_version": "1.21.80", "minecraft:shadow_settings": {"shadow_style": "soft_shadows"}}


# --------------------------------------------------------------------------
# Writer
# --------------------------------------------------------------------------

def _dump(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fp:
        json.dump(data, fp, indent=2)
        fp.write("\n")


def write_config(out, vanilla_dir):
    files = []

    def put(rel, data):
        _dump(os.path.join(out, rel), data)
        files.append(rel)

    # Overworld profiles
    for pid, p in PROFILES.items():
        put(f"atmospherics/{pid}.json" if pid != "default" else "atmospherics/atmospherics.json",
            atmosphere_json(pid, p))
        put(f"lighting/{pid}.json" if pid != "default" else "lighting/global.json", lighting_json(pid, p))
        put(f"color_grading/{pid}.json" if pid != "default" else "color_grading/color_grading.json",
            grading_json(pid, p.get("grade", {})))

    # Nether
    for pid, p in NETHER.items():
        put(f"atmospherics/nether_{pid}.json", {
            "format_version": "1.21.40",
            "minecraft:atmosphere_settings": {
                "description": {"identifier": f"{NS}:nether_{pid}_atmospherics"},
                "horizon_blend_stops": {"min": 0.0, "start": 0.8, "mie_start": 0.5, "max": 1.0},
                "rayleigh_strength": kf({0.0: 0.15, 1.0: 0.15}),
                "sun_mie_strength": kf({0.0: 0.0, 1.0: 0.0}),
                "moon_mie_strength": kf({0.0: 0.0, 1.0: 0.0}),
                "sky_zenith_color": kf({0.0: p["zenith"], 1.0: p["zenith"]}),
                "sky_horizon_color": kf({0.0: p["horizon"], 1.0: p["horizon"]}),
            },
        })
        amb_col, amb_ill = p["ambient"]
        put(f"lighting/nether_{pid}.json",
            flat_lighting_json(f"nether_{pid}", 100.0, [255, 255, 255], amb_ill, amb_col, sky=1.0))
        put(f"color_grading/nether_{pid}.json", grading_json(f"nether_{pid}", p["grade"]))

    # End: void sky with violet flashes
    put("atmospherics/end.json", {
        "format_version": "1.21.40",
        "minecraft:atmosphere_settings": {
            "description": {"identifier": f"{NS}:end_atmospherics"},
            "horizon_blend_stops": {"min": 0.0, "start": 0.8, "mie_start": 0.5, "max": 1.0},
            "rayleigh_strength": kf({0.0: 0.3, 1.0: 0.3}),
            "sun_mie_strength": kf({0.0: 0.0, 1.0: 0.0}),
            "moon_mie_strength": kf({0.0: 0.0, 1.0: 0.0}),
            "sky_zenith_color": kf({0.0: [10, 6, 20], 1.0: [10, 6, 20]}),
            "sky_horizon_color": kf({0.0: [36, 22, 52], 1.0: [36, 22, 52]}),
        },
    })
    put("lighting/end.json", flat_lighting_json("end", 100.0, [236, 224, 255], 0.14, [214, 196, 255],
                                                flash={"illuminance": 6.0, "color": [206, 110, 255]}))
    put("color_grading/end.json", grading_json("end", dict(temperature=7400, saturation=1.06, contrast=1.08)))

    # Water
    for wid, w in WATERS.items():
        put(f"water/{wid}.json" if wid != "lake" else "water/water.json", water_json(wid, w))

    put("shadows/global.json", shadows_json())
    put("pbr/global.json", pbr_json())
    put("local_lighting/local_lighting.json", local_lighting_json())

    # Biomes and their fogs
    vb = os.path.join(vanilla_dir, "biomes")
    vf = os.path.join(vanilla_dir, "fogs")
    vanilla_fogs = {}
    for f in os.listdir(vf):
        d = json.load(open(os.path.join(vf, f)))
        fid = d["minecraft:fog_settings"]["description"]["identifier"]
        vanilla_fogs[fid] = d
    biome_map = {}
    for f in sorted(os.listdir(vb)):
        name = f.replace(".client_biome.json", "")
        d = copy.deepcopy(json.load(open(os.path.join(vb, f))))
        comp = d["minecraft:client_biome"]["components"]
        prof = biome_profile(name)
        wat = biome_water(name)
        if prof.startswith("nether:"):
            pid = "nether_" + prof.split(":")[1]
            fog_p = dict(NETHER[prof.split(":")[1]]["fog"], uniform=True)
        elif prof == "end":
            pid = "end"
            fog_p = dict(density=0.04, scattering=[0.03, 0.02, 0.045], g=0.6, uniform=True)
        else:
            pid = prof
            fog_p = PROFILES[prof].get("fog", DEFAULT_FOG)
        comp["minecraft:atmosphere_identifier"] = {"atmosphere_identifier": f"{NS}:{pid}_atmospherics"}
        comp["minecraft:lighting_identifier"] = {"lighting_identifier": f"{NS}:{pid}_lighting"}
        comp["minecraft:color_grading_identifier"] = {"color_grading_identifier": f"{NS}:{pid}_color_grading"}
        comp["minecraft:water_identifier"] = {"water_identifier": f"{NS}:{wat}_water"}

        # Fog: keep vanilla distance fog (classic look, underwater visibility),
        # add Halcyon volumetrics.
        old = comp.get("minecraft:fog_appearance", {}).get("fog_identifier")
        base = vanilla_fogs.get(old) or vanilla_fogs.get("minecraft:fog_default")
        fog = copy.deepcopy(base)
        fs = fog["minecraft:fog_settings"]
        new_id = f"{NS}:fog_{name}"
        fs["description"]["identifier"] = new_id
        water_kind = "murky" if wat in ("swamp", "mangrove", "river", "sulfur", "pale") else (
            "clear" if wat in ("tropical", "lukewarm", "oasis", "deep") else "default")
        fs["volumetric"] = volumetric(fog_p, water_kind)
        fog["format_version"] = "1.21.90"
        put(f"fogs/{NS}_{name}.json", fog)
        comp["minecraft:fog_appearance"] = {"fog_identifier": new_id}
        put(f"biomes/{f}", d)
        biome_map[name] = {"profile": pid, "water": wat}

    # Default fog for anything without a biome fog (custom biomes, etc.)
    fog = copy.deepcopy(vanilla_fogs["minecraft:fog_default"])
    fog["format_version"] = "1.21.90"
    fog["minecraft:fog_settings"]["volumetric"] = volumetric(DEFAULT_FOG)
    put("fogs/default_fog_setting.json", fog)
    return files, biome_map

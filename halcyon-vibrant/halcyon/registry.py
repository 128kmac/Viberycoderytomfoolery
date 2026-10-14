"""Texture registry: recipes register the vanilla texture names they replace."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

REGISTRY: dict[str, "Entry"] = {}


@dataclass
class Entry:
    name: str                       # path under textures/blocks, no extension
    fn: Callable                    # fn(ctx, seed) -> Material
    exts: tuple = ("png",)          # colour file extensions to emit
    frames: int = 1                 # flipbook frames stacked vertically
    width_mul: int = 1              # flowing fluids use 2x wide textures
    tga_alpha: object = None        # alpha forced into the .tga variant
    tags: tuple = field(default_factory=tuple)


def tex(name, exts=("png",), frames=1, width_mul=1, tga_alpha=None, tags=()):
    def deco(fn):
        if name in REGISTRY:
            raise ValueError(f"duplicate texture {name}")
        REGISTRY[name] = Entry(name, fn, tuple(exts), frames, width_mul, tga_alpha, tuple(tags))
        return fn
    return deco


def add(name, fn, **kw):
    tex(name, **kw)(fn)

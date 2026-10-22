#!/usr/bin/env bash
# Fetches ModMorpher from its official repository and installs Python dependencies.
# ModMorpher isn't copied into this repo; its license asks that it stay downstream of the original.
set -euo pipefail
cd "$(dirname "$0")"

if [ -d vendor/Modmorpher/.git ]; then
  git -C vendor/Modmorpher pull --ff-only
else
  mkdir -p vendor
  git clone --depth 1 https://github.com/Indozilla1234/Modmorpher vendor/Modmorpher
fi

python3 -m pip install -r requirements.txt

if ! java -version >/dev/null 2>&1; then
  echo "WARNING: Java isn't installed. ModMorpher needs OpenJDK 21+ to decompile mods." >&2
fi
echo "Ready. Start the site with: python3 app.py   (then open http://localhost:8000)"

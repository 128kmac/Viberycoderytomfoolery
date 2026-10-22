# ModMorpher Web

A small website for [ModMorpher](https://github.com/Indozilla1234/Modmorpher):
drop in a Java Edition mod (`.jar`), watch it convert, download the Bedrock `.mcaddon`
and the porting notes listing what needs fixing by hand.

## Run it on your computer

Needs Python 3.10+, Git and Java (OpenJDK 21+).

```bash
cd modmorpher-web
./setup.sh        # downloads ModMorpher and installs Python packages
python3 app.py    # then open http://localhost:8000
```

## Run it with Docker

```bash
cd modmorpher-web
docker build -t modmorpher-web .
docker run -p 8000:8000 modmorpher-web
```

The same Dockerfile works on hosts that build from a Dockerfile, such as Render, Railway, Fly.io
or a Hugging Face Space (Docker type). Give it at least 1 GB of memory; decompiling is
the heavy part.

## Settings (environment variables)

| Variable | Default | What it does |
|---|---|---|
| `PORT` | `8000` | Port to listen on |
| `MAX_UPLOAD_MB` | `200` | Largest `.jar` accepted |
| `MAX_PARALLEL_JOBS` | `1` | Conversions run at once (others wait in a queue) |
| `JOB_TIMEOUT_S` | `1200` | Stop a conversion after this many seconds |
| `JOB_TTL_S` | `3600` | Delete finished jobs and their files after this many seconds |
| `MODMORPHER_DIR` | `vendor/Modmorpher` | Where the ModMorpher checkout lives |

## License note

ModMorpher is © Indozilla1234 under its own Source Available License. This site doesn't
include ModMorpher's code; it downloads the official version and runs it. That license only
allows converting mods you made or have written permission to modify, and it doesn't allow
commercial use without permission, so check with Indozilla1234 before running this as a
public or paid service.

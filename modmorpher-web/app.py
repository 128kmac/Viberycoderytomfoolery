"""Web front end for ModMorpher (https://github.com/Indozilla1234/Modmorpher).

Upload a Java Edition mod (.jar), ModMorpher converts it, download the .mcaddon.
ModMorpher itself is not bundled here: setup.sh / the Dockerfile fetch it from
the official repository, and MODMORPHER_DIR points at that checkout.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import zipfile

from flask import Flask, abort, jsonify, render_template, request, send_file

HERE = os.path.dirname(os.path.abspath(__file__))
MODMORPHER_DIR = os.environ.get("MODMORPHER_DIR", os.path.join(HERE, "vendor", "Modmorpher"))
MODMORPHER_SCRIPT = os.path.join(MODMORPHER_DIR, "modmorpher.py")
JOBS_ROOT = os.environ.get("JOBS_DIR", os.path.join(tempfile.gettempdir(), "modmorpher-jobs"))
MAX_UPLOAD_MB = int(os.environ.get("MAX_UPLOAD_MB", "200"))
JOB_TIMEOUT_S = int(os.environ.get("JOB_TIMEOUT_S", "1200"))
JOB_TTL_S = int(os.environ.get("JOB_TTL_S", "3600"))
MAX_PARALLEL = int(os.environ.get("MAX_PARALLEL_JOBS", "1"))

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_UPLOAD_MB * 1024 * 1024

jobs = {}
jobs_lock = threading.Lock()
run_slots = threading.Semaphore(MAX_PARALLEL)

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
PROGRESS_RE = re.compile(r"^\s*(\S.*?)\s{2,}[━╌]+\s+(\d+)%")
SAFE_NAME_RE = re.compile(r"[^A-Za-z0-9._-]+")


def clean_log(raw):
    """Turn ModMorpher's progress-bar output into plain lines."""
    text = ANSI_RE.sub("", raw).replace("\r", "\n")
    return [line.rstrip() for line in text.split("\n") if line.strip()]


def read_progress(log_path):
    """Return (stage, percent, readable log lines) from a job's log so far."""
    try:
        with open(log_path, encoding="utf-8", errors="replace") as f:
            lines = clean_log(f.read())
    except FileNotFoundError:
        return None, 0, []
    stage, pct, readable = None, 0, []
    for line in lines:
        m = PROGRESS_RE.match(line)
        if m:
            stage, pct = m.group(1), int(m.group(2))
        else:
            readable.append(line)
    return stage, pct, readable


def summarize_addon(path):
    """Count files per pack folder (e.g. 'bp/entities': 26)."""
    counts = {}
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            parts = name.split("/")
            if name.endswith("/") or len(parts) < 3:
                continue
            key = f"{parts[0]}/{parts[1]}"
            counts[key] = counts.get(key, 0) + 1
    return dict(sorted(counts.items(), key=lambda kv: -kv[1]))


def run_job(job_id):
    job = jobs[job_id]
    workdir = job["dir"]
    log_path = os.path.join(workdir, "run.log")
    job["status"] = "queued"
    with run_slots:
        job["status"] = "running"
        job["started"] = time.time()
        try:
            with open(log_path, "w") as log:
                proc = subprocess.run(
                    [sys.executable, MODMORPHER_SCRIPT],
                    cwd=workdir,
                    stdin=subprocess.DEVNULL,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    timeout=JOB_TIMEOUT_S,
                    env={**os.environ, "PYTHONUNBUFFERED": "1"},
                )
            addon = os.path.join(workdir, "Bedrock_Pack.mcaddon")
            if proc.returncode == 0 and os.path.isfile(addon):
                job["summary"] = summarize_addon(addon)
                job["status"] = "done"
            else:
                job["status"] = "failed"
                job["error"] = f"ModMorpher exited with code {proc.returncode} and produced no .mcaddon."
        except subprocess.TimeoutExpired:
            job["status"] = "failed"
            job["error"] = f"Conversion took longer than {JOB_TIMEOUT_S // 60} minutes and was stopped."
        except Exception as e:  # keep the job visible instead of a silent thread death
            job["status"] = "failed"
            job["error"] = str(e)
        finally:
            job["finished"] = time.time()
            # The .jar and the unpacked pack folder aren't needed once the addon exists.
            for name in os.listdir(workdir):
                p = os.path.join(workdir, name)
                if name.endswith(".jar"):
                    os.remove(p)
                elif os.path.isdir(p):
                    shutil.rmtree(p, ignore_errors=True)


def reap_old_jobs():
    while True:
        time.sleep(300)
        cutoff = time.time() - JOB_TTL_S
        with jobs_lock:
            stale = [jid for jid, j in jobs.items() if j.get("finished") and j["finished"] < cutoff]
            for jid in stale:
                shutil.rmtree(jobs.pop(jid)["dir"], ignore_errors=True)


def get_job(job_id):
    job = jobs.get(job_id)
    if job is None:
        abort(404)
    return job


@app.get("/")
def index():
    return render_template(
        "index.html",
        max_upload_mb=MAX_UPLOAD_MB,
        ready=os.path.isfile(MODMORPHER_SCRIPT),
    )


@app.post("/api/convert")
def convert():
    if not os.path.isfile(MODMORPHER_SCRIPT):
        return jsonify(error="ModMorpher isn't installed on this server. Run setup.sh first."), 503
    if request.form.get("permission") != "yes":
        return jsonify(error="Please confirm you made this mod or have permission to convert it."), 400
    upload = request.files.get("mod")
    if upload is None or not upload.filename:
        return jsonify(error="No file uploaded."), 400
    if not upload.filename.lower().endswith(".jar"):
        return jsonify(error="That isn't a .jar file."), 400

    job_id = uuid.uuid4().hex[:12]
    workdir = os.path.join(JOBS_ROOT, job_id)
    os.makedirs(workdir)
    safe_name = SAFE_NAME_RE.sub("_", os.path.basename(upload.filename)) or "mod.jar"
    jar_path = os.path.join(workdir, safe_name)
    upload.save(jar_path)
    if not zipfile.is_zipfile(jar_path):
        shutil.rmtree(workdir, ignore_errors=True)
        return jsonify(error="That file isn't a valid .jar (it isn't a zip archive)."), 400

    with jobs_lock:
        jobs[job_id] = {"dir": workdir, "mod": safe_name, "status": "queued", "created": time.time()}
    threading.Thread(target=run_job, args=(job_id,), daemon=True).start()
    return jsonify(id=job_id)


@app.get("/api/jobs/<job_id>")
def job_status(job_id):
    job = get_job(job_id)
    stage, pct, lines = read_progress(os.path.join(job["dir"], "run.log"))
    elapsed_end = job.get("finished") or time.time()
    return jsonify(
        status=job["status"],
        mod=job["mod"],
        stage=stage,
        percent=pct,
        log=lines[-40:],
        error=job.get("error"),
        summary=job.get("summary"),
        elapsed=round(elapsed_end - job.get("started", elapsed_end)),
        has_notes=os.path.isfile(os.path.join(job["dir"], "PORTING_NOTES.txt")),
    )


@app.get("/api/jobs/<job_id>/addon")
def download_addon(job_id):
    job = get_job(job_id)
    path = os.path.join(job["dir"], "Bedrock_Pack.mcaddon")
    if not os.path.isfile(path):
        abort(404)
    name = os.path.splitext(job["mod"])[0] + ".mcaddon"
    return send_file(path, as_attachment=True, download_name=name)


@app.get("/api/jobs/<job_id>/notes")
def porting_notes(job_id):
    job = get_job(job_id)
    path = os.path.join(job["dir"], "PORTING_NOTES.txt")
    if not os.path.isfile(path):
        abort(404)
    return send_file(path, mimetype="text/plain")


@app.errorhandler(413)
def too_large(_):
    return jsonify(error=f"File is bigger than the {MAX_UPLOAD_MB} MB limit."), 413


os.makedirs(JOBS_ROOT, exist_ok=True)
threading.Thread(target=reap_old_jobs, daemon=True).start()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))

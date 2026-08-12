"""\"EasyLoan API\" - deliberately insecure app used ONLY for the demo.

Intentionally includes:
  - hardcoded AWS keys and a plaintext DB password
  - an f-string SQL injection in GET /api/v1/user
  - a raw shell_exec style endpoint (RCE for demo)
  - debug = True  (leaks stack traces)
"""
import os
import sqlite3
import subprocess

from flask import Flask, jsonify, request

# ─── HARDCODED SECRETS (BAD) ──────────────────────────────────────────────────
DB_PASSWORD = "S3cr3t_DB_Pass_123"
AWS_ACCESS_KEY = "AKIAOSFODNN7EXAMPLE"
AWS_SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

app = Flask(__name__)
app.config["DEBUG"] = True


def get_db():
    db = sqlite3.connect(os.environ.get("DB_PATH", "app.db"))
    db.execute(
        "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT)"
    )
    db.execute("INSERT OR IGNORE INTO users VALUES (1, 'admin'), (2, 'sara')")
    db.commit()
    return db


@app.route("/api/v1/user", methods=["GET"])
def get_user():
    """VULN: /api/v1/user?id=1 OR 1=1 --"""
    uid = request.args.get("id", "1")
    db = get_db()
    cur = db.execute(f"SELECT * FROM users WHERE id = {uid}")  # f-string SQLi
    return jsonify(cur.fetchall())


@app.route("/api/v1/exec", methods=["POST"])
def execute():
    """VULN: arbitrary command execution (demo ONLY)."""
    cmd = request.json.get("cmd", "id")
    return jsonify({"output": subprocess.check_output(cmd, shell=True).decode()})


@app.route("/api/v1/health", methods=["GET"])
def health():
    return {"status": "ok", "version": "1.4.0-beta", "running_as": os.getuid()}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)
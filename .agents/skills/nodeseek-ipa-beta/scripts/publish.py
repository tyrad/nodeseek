#!/usr/bin/env python3
"""Upload and verify an IPA, or list existing builds. Python 3.8+."""
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
from urllib.parse import urlencode, urlsplit


def git(*args):
    p = subprocess.run(["git", *args], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else ""


def request(origin, key, method, route, body=None, size=0, boundary=""):
    conn_type = http.client.HTTPSConnection if origin.scheme == "https" else http.client.HTTPConnection
    conn = conn_type(origin.hostname, origin.port, timeout=180)
    try:
        conn.putrequest(method, route)
        conn.putheader("Authorization", "Bearer " + key)
        if body is not None:
            conn.putheader("Content-Type", "multipart/form-data; boundary=" + boundary)
            conn.putheader("Content-Length", str(size))
        conn.endheaders()
        if body is not None:
            for chunk in body:
                conn.send(chunk)
        response = conn.getresponse()
        data = response.read()
        if response.status not in (200, 201):
            raise ValueError("HTTP %d: %s" % (response.status, data[:200].decode(errors="replace")))
        return json.loads(data)
    finally:
        conn.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("action", choices=["upload", "list"])
    ap.add_argument("ipa", nargs="?")
    ap.add_argument("--worktree")
    ap.add_argument("--branch")
    ap.add_argument("--commit")
    opts = ap.parse_args()
    origin = urlsplit("https://install.mistj.dev")
    key = os.environ.get("IOS_SHELF_API_KEY", "")
    if not re.fullmatch(r"[0-9a-f]{16}\.[0-9a-f]{64}", key):
        ap.error("set IOS_SHELF_API_KEY to an active iOS Shelf agent key")
    route = "/api/builds"
    if opts.action == "list":
        query = "?" + urlencode({"worktree": opts.worktree}) if opts.worktree else ""
        print(json.dumps(request(origin, key, "GET", route + query), ensure_ascii=False, indent=2))
        return
    if not opts.ipa:
        ap.error("upload requires a signed IPA")
    path = Path(opts.ipa)
    root = git("rev-parse", "--show-toplevel")
    tree = opts.worktree or (Path(root).name if root else "")
    if not tree:
        ap.error("run inside the source worktree or supply --worktree")
    fields = {"worktree": tree, "branch": opts.branch if opts.branch is not None else git("branch", "--show-current"),
              "commit": opts.commit if opts.commit is not None else git("rev-parse", "--short=12", "HEAD")}
    boundary = secrets.token_hex(24)
    head = b""
    for k, v in fields.items():
        head += ('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' % (boundary, k, v)).encode()
    head += ('--%s\r\nContent-Disposition: form-data; name="ipa"; filename="build.ipa"\r\nContent-Type: application/octet-stream\r\n\r\n' % boundary).encode()
    tail = ("\r\n--%s--\r\n" % boundary).encode()
    sha = hashlib.sha256()
    with path.open("rb") as f:
        def chunks():
            yield head
            for chunk in iter(lambda: f.read(1 << 20), b""):
                sha.update(chunk)
                yield chunk
            yield tail
        result = request(origin, key, "POST", route, chunks(), len(head) + os.fstat(f.fileno()).st_size + len(tail), boundary)
    if result.get("sha256") != sha.hexdigest() or result.get("worktree") != tree:
        raise ValueError("uploaded build metadata mismatch")
    matches = request(origin, key, "GET", route + "?" + urlencode({"worktree": tree}))
    if not any(b["id"] == result["id"] for b in matches):
        raise ValueError("uploaded build missing from worktree list")
    result["install_page"] = origin.geturl() + "/?" + urlencode({"worktree": tree})
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, ValueError, http.client.HTTPException) as exc:
        sys.exit(str(exc))

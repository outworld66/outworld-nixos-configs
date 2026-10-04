#!/usr/bin/env python3
"""Reconcile the media services after their NixOS units have started."""

import http.cookiejar
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

MEDIA_ROOT = "/srv/media"


def secret(name):
    return Path(f"/run/secrets/media/{name}").read_text().strip()


def request(base, path, *, method="GET", data=None, headers=None, cookies=None, retries=60):
    body = None
    request_headers = dict(headers or {})
    if data is not None:
        if isinstance(data, dict):
            body = json.dumps(data).encode()
            request_headers.setdefault("Content-Type", "application/json")
        else:
            body = data
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cookies)
        if cookies is not None
        else urllib.request.BaseHandler()
    )
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                base + path, data=body, headers=request_headers, method=method
            )
            with opener.open(req, timeout=10) as response:
                payload = response.read()
                if not payload:
                    return None
                content_type = response.headers.get("Content-Type", "")
                return json.loads(payload) if "json" in content_type else payload
        except urllib.error.HTTPError as error:
            if error.code in (429, 500, 502, 503, 504) and attempt + 1 < retries:
                time.sleep(2)
                continue
            raise RuntimeError(f"{method} {path}: HTTP {error.code}") from None
        except (urllib.error.URLError, TimeoutError):
            if attempt + 1 == retries:
                raise RuntimeError(f"{method} {path}: service did not become ready") from None
            time.sleep(2)


def qbit_login(password):
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    data = urllib.parse.urlencode({"username": "admin", "password": password}).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8181/api/v2/auth/login",
        data=data,
        headers={"Referer": "http://127.0.0.1:8181/"},
    )
    for attempt in range(60):
        try:
            with opener.open(req, timeout=10) as response:
                body = response.read()
                return opener, response.status == 204 or body == b"Ok."
        except urllib.error.HTTPError:
            return opener, False
        except urllib.error.URLError:
            if attempt == 59:
                raise RuntimeError("qBittorrent Web UI did not become ready") from None
            time.sleep(2)


def qbit_request(opener, path, data=None):
    body = urllib.parse.urlencode(data or {}).encode() if data is not None else None
    req = urllib.request.Request(
        f"http://127.0.0.1:8181/api/v2/{path}",
        data=body,
        headers={"Referer": "http://127.0.0.1:8181/"},
    )
    with opener.open(req, timeout=15) as response:
        return response.read()


def configure_qbittorrent():
    password = secret("qbittorrent-webui-password")
    opener, valid = qbit_login(password)
    if not valid:
        logs = subprocess.run(
            ["journalctl", "-u", "qbittorrent.service", "-b", "--no-pager", "-o", "cat"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        matches = re.findall(
            r"(?:temporary password is provided for this session|administrator password is):\s*(\S+)",
            logs,
            flags=re.IGNORECASE,
        )
        if not matches:
            raise RuntimeError("qBittorrent login failed and no first-run password was found")
        opener, valid = qbit_login(matches[-1])
        if not valid:
            raise RuntimeError("qBittorrent first-run login failed")
        preferences = {
            "web_ui_username": "admin",
            "web_ui_password": password,
            "save_path": f"{MEDIA_ROOT}/downloads/complete",
            "temp_path_enabled": True,
            "temp_path": f"{MEDIA_ROOT}/downloads/incomplete",
        }
        qbit_request(opener, "app/setPreferences", {"json": json.dumps(preferences)})
        opener, valid = qbit_login(password)
        if not valid:
            raise RuntimeError("qBittorrent did not accept its SOPS password")

    categories = json.loads(qbit_request(opener, "torrents/categories"))
    for category in ("movies", "tv", "books", "streamline"):
        save_path = f"{MEDIA_ROOT}/downloads/complete/{category}"
        if category not in categories:
            qbit_request(
                opener,
                "torrents/createCategory",
                {"category": category, "savePath": save_path},
            )
        elif categories[category]["savePath"] != save_path:
            qbit_request(
                opener,
                "torrents/editCategory",
                {"category": category, "savePath": save_path},
            )
    print("qBittorrent credentials, paths, and categories are configured")


def jackett_api(key, indexer, **params):
    query = urllib.parse.urlencode({"apikey": key, **params})
    path = f"/api/v2.0/indexers/{indexer}/results/torznab/api?{query}"
    return request("http://127.0.0.1:9117", path)


def jellyfin_request(
    path, *, token=None, method="GET", data=None, device_id="rico-media-bootstrap"
):
    authorization = f'MediaBrowser Client="Media Stack Bootstrap", Device="Rico", DeviceId="{device_id}", Version="1.0"'
    if token:
        authorization += f', Token="{token}"'
    return request(
        "http://127.0.0.1:8096",
        path,
        method=method,
        data=data,
        headers={"Authorization": authorization},
    )


def configure_jellyfin():
    password = secret("jellyfin-admin-password")
    auth = jellyfin_request(
        "/Users/AuthenticateByName",
        method="POST",
        data={"Username": "admin", "Pw": password},
    )
    token = auth["AccessToken"]
    libraries = jellyfin_request("/Library/VirtualFolders", token=token)
    for name, collection, path in (
        ("Movies", "movies", f"{MEDIA_ROOT}/library/movies"),
        ("TV", "tvshows", f"{MEDIA_ROOT}/library/tv"),
    ):
        library = next((item for item in libraries if item["Name"] == name), None)
        if library is None:
            jellyfin_request(
                "/Library/VirtualFolders?"
                + urllib.parse.urlencode(
                    {"name": name, "collectionType": collection, "paths": path}
                ),
                token=token,
                method="POST",
            )
            continue
        old_paths = [
            current
            for current in library.get("Locations", [])
            if current.startswith("/data") and "/media/library/" in current
        ]
        if path not in library.get("Locations", []):
            jellyfin_request(
                "/Library/VirtualFolders/Paths?refreshLibrary=true",
                token=token,
                method="POST",
                data={"Name": name, "Path": path},
            )
        for old_path in old_paths:
            jellyfin_request(
                "/Library/VirtualFolders/Paths?"
                + urllib.parse.urlencode(
                    {"name": name, "path": old_path, "refreshLibrary": "true"}
                ),
                token=token,
                method="DELETE",
            )
    print("Jellyfin Movies and TV libraries are configured")
    return token


def configure_streamline_jellyfin_key():
    password = secret("jellyfin-admin-password")
    auth = jellyfin_request(
        "/Users/AuthenticateByName",
        method="POST",
        data={"Username": "admin", "Pw": password},
        device_id="rico-streamline-jellyfin-key",
    )
    token = auth["AccessToken"]

    def keys():
        result = jellyfin_request(
            "/Auth/Keys", token=token, device_id="rico-streamline-jellyfin-key"
        )
        return result if isinstance(result, list) else result.get("Items", [])

    matches = [key for key in keys() if key.get("AppName") == "Streamline"]
    if not matches:
        jellyfin_request(
            "/Auth/Keys?" + urllib.parse.urlencode({"app": "Streamline"}),
            token=token,
            method="POST",
            device_id="rico-streamline-jellyfin-key",
        )
        matches = [key for key in keys() if key.get("AppName") == "Streamline"]
    if not matches or not matches[0].get("AccessToken"):
        raise RuntimeError("Jellyfin did not return the Streamline API key")

    path = Path("/var/lib/streamline/jellyfin-api-key")
    path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".new")
    temporary.write_text(matches[0]["AccessToken"] + "\n")
    temporary.chmod(0o400)
    temporary.replace(path)
    print("Streamline Jellyfin API key is configured")


def configure_bindery():
    base = "http://127.0.0.1:8787"
    cookies = http.cookiejar.CookieJar()
    password = secret("bindery-admin-password")
    try:
        request(base, "/api/v1/auth/setup", method="POST", data={"username": "admin", "password": password}, cookies=cookies)
    except RuntimeError as error:
        if "HTTP 409" not in str(error):
            raise
        request(base, "/api/v1/auth/login", method="POST", data={"username": "admin", "password": password}, cookies=cookies)
    csrf = request(base, "/api/v1/auth/csrf", cookies=cookies)["csrfToken"]
    headers = {"X-CSRF-Token": csrf, "X-Requested-With": "bindery-ui"}
    clients = request(base, "/api/v1/downloadclient", cookies=cookies, headers=headers)
    client = {
        "name": "qBittorrent",
        "type": "qbittorrent",
        "host": "127.0.0.1",
        "port": 8181,
        "username": "admin",
        "password": secret("qbittorrent-webui-password"),
        "category": "books",
        "categoryAudiobook": "books",
        "enabled": True,
        "priority": 1,
    }
    existing = next((item for item in clients if item["name"] == "qBittorrent"), None)
    if existing:
        client["id"] = existing["id"]
        request(base, f"/api/v1/downloadclient/{existing['id']}", method="PUT", data=client, cookies=cookies, headers=headers)
    else:
        request(base, "/api/v1/downloadclient", method="POST", data=client, cookies=cookies, headers=headers)

    indexers = request(base, "/api/v1/indexer", cookies=cookies, headers=headers)
    if not any(item["name"] == "Jackett" for item in indexers):
        jackett = json.loads(
            Path("/var/lib/jackett/.config/Jackett/ServerConfig.json").read_text()
        )
        request(
            base,
            "/api/v1/indexer",
            method="POST",
            data={
                "name": "Jackett",
                "type": "torznab",
                "url": "http://127.0.0.1:9117/api/v2.0/indexers/all/results/torznab/api",
                "apiKey": jackett["APIKey"],
                "categories": [7000],
                "priority": 1,
                "enabled": True,
                "supportsSearch": True,
            },
            cookies=cookies,
            headers=headers,
        )
    print("Bindery admin and qBittorrent download client are configured")


def main():
    configure_qbittorrent()
    configure_jellyfin()
    configure_bindery()


if __name__ == "__main__":
    if sys.argv[1:] == ["--streamline-jellyfin-key"]:
        configure_streamline_jellyfin_key()
    else:
        main()

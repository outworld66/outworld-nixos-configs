#!/usr/bin/env python3
"""Reconcile the media services after their NixOS units have started."""

import http.cookiejar
import json
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

MEDIA_ROOT = "/srv/media"


def secret(name):
    return Path(f"/run/secrets/media/{name}").read_text().strip()


def request(base, path, *, method="GET", data=None, headers=None, cookies=None):
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
    for attempt in range(60):
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
            if error.code in (429, 500, 502, 503, 504) and attempt < 59:
                time.sleep(2)
                continue
            raise RuntimeError(f"{method} {path}: HTTP {error.code}") from None
        except (urllib.error.URLError, TimeoutError):
            if attempt == 59:
                raise RuntimeError(f"{method} {path}: service did not become ready") from None
            time.sleep(2)


def arr_api(port, data_dir, path, *, method="GET", data=None):
    config = ET.parse(Path(data_dir) / "config.xml").getroot()
    key = config.findtext("ApiKey")
    return arr_request(port, key, path, method=method, data=data)


def arr_request(port, key, path, *, method="GET", data=None):
    return request(
        f"http://127.0.0.1:{port}",
        f"/api/v3/{path}",
        method=method,
        data=data,
        headers={"X-Api-Key": key},
    )


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
    for category in ("movies", "tv", "books"):
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


def ensure_arr_root(port, data_dir, path):
    folders = arr_api(port, data_dir, "rootfolder")
    if not any(folder["path"] == path for folder in folders):
        arr_api(port, data_dir, "rootfolder", method="POST", data={"path": path})
    media_type = "movie" if path.endswith("/movies") else "series"
    managed = arr_api(port, data_dir, media_type)
    for folder in folders:
        if (
            folder["path"].startswith("/data")
            and "/media/library/" in folder["path"]
            and not any(item.get("rootFolderPath") == folder["path"] for item in managed)
        ):
            arr_api(port, data_dir, f"rootfolder/{folder['id']}", method="DELETE")


def ensure_arr_download_client(port, data_dir, category):
    clients = arr_api(port, data_dir, "downloadclient")
    existing = next((item for item in clients if item["name"] == "qBittorrent"), None)
    schema = next(
        item
        for item in arr_api(port, data_dir, "downloadclient/schema")
        if item["implementation"] == "QBittorrent"
    )
    values = {
        "host": "127.0.0.1",
        "port": 8181,
        "username": "admin",
        "password": secret("qbittorrent-webui-password"),
        "movieCategory": category,
        "tvCategory": category,
    }
    for field in schema["fields"]:
        if field["name"] in values:
            field["value"] = values[field["name"]]
    schema.update({"name": "qBittorrent", "enable": True, "protocol": "torrent", "priority": 1})
    if existing:
        schema["id"] = existing["id"]
        path = f"downloadclient/{existing['id']}"
        method = "PUT"
    else:
        path = "downloadclient"
        method = "POST"
    arr_api(port, data_dir, path, method=method, data=schema)


def ensure_arr_indexer(port, data_dir, categories):
    jackett = json.loads(
        Path("/var/lib/jackett/.config/Jackett/ServerConfig.json").read_text()
    )
    key = jackett["APIKey"]
    indexers = arr_api(port, data_dir, "indexer")
    existing = next((item for item in indexers if item.get("name") == "Jackett"), None)
    schema = next(
        item
        for item in arr_api(port, data_dir, "indexer/schema")
        if item["implementation"] == "Torznab"
    )
    values = {
        "baseUrl": "http://127.0.0.1:9117",
        "apiPath": "/api/v2.0/indexers/anilibria/results/torznab/api",
        "apiKey": key,
        "categories": categories,
    }
    for field in schema["fields"]:
        if field["name"] in values:
            field["value"] = values[field["name"]]
    schema.update(
        {
            "name": "Jackett",
            "enable": True,
            "enableRss": True,
            "enableAutomaticSearch": True,
            "enableInteractiveSearch": True,
            "protocol": "torrent",
            "priority": 1,
        }
    )
    if existing:
        schema["id"] = existing["id"]
        path = f"indexer/{existing['id']}"
        method = "PUT"
    else:
        path = "indexer"
        method = "POST"
    arr_api(port, data_dir, path, method=method, data=schema)


def configure_arr(port, data_dir, root, category, indexer_categories=None):
    ensure_arr_root(port, data_dir, root)
    ensure_arr_download_client(port, data_dir, category)
    if indexer_categories is not None:
        ensure_arr_indexer(port, data_dir, indexer_categories)


def jellyfin_request(path, *, token=None, method="GET", data=None):
    authorization = 'MediaBrowser Client="Media Stack Bootstrap", Device="Rico", DeviceId="rico-media-bootstrap", Version="1.0"'
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


def seerr_request(path, *, method="GET", data=None, cookies):
    return request("http://127.0.0.1:5055", path, method=method, data=data, cookies=cookies)


def configure_seerr():
    password = secret("jellyfin-admin-password")
    cookies = http.cookiejar.CookieJar()
    public = request("http://127.0.0.1:5055", "/api/v1/settings/public")
    body = {"username": "admin", "password": password}
    if public["mediaServerType"] == 4:
        body.update(
            {
                "hostname": "127.0.0.1",
                "port": 8096,
                "useSsl": False,
                "urlBase": "",
                "serverType": 2,
            }
        )
    seerr_request("/api/v1/auth/jellyfin", method="POST", data=body, cookies=cookies)

    main = seerr_request("/api/v1/settings/main", cookies=cookies)
    main.pop("apiKey", None)
    main.update(
        {
            "applicationTitle": "Media Requests",
            "applicationUrl": "https://requests.outworld66.ru",
            "cacheImages": True,
            "defaultPermissions": 32,
            "localLogin": False,
            "mediaServerLogin": True,
            "newPlexLogin": True,
        }
    )
    seerr_request("/api/v1/settings/main", method="POST", data=main, cookies=cookies)
    network = seerr_request("/api/v1/settings/network", cookies=cookies)
    restart_after_configure = not network.get("forceIpv4First", False)
    network["forceIpv4First"] = True
    seerr_request(
        "/api/v1/settings/network",
        method="POST",
        data=network,
        cookies=cookies,
    )
    jellyfin = seerr_request("/api/v1/settings/jellyfin", cookies=cookies)
    for key in ("name", "libraries", "serverId"):
        jellyfin.pop(key, None)
    jellyfin.update({"externalHostname": "https://jellyfin.outworld66.ru"})
    seerr_request("/api/v1/settings/jellyfin", method="POST", data=jellyfin, cookies=cookies)

    libraries = seerr_request("/api/v1/settings/jellyfin/library?sync=true", cookies=cookies)
    enabled = [item["id"] for item in libraries if item["name"] in ("Movies", "TV")]
    if len(enabled) != 2:
        raise RuntimeError("Seerr could not find both Jellyfin libraries")
    seerr_request(
        "/api/v1/settings/jellyfin/library?enable=" + urllib.parse.quote(",".join(enabled)),
        cookies=cookies,
    )

    for kind, port, root in (
        ("radarr", 7878, f"{MEDIA_ROOT}/library/movies"),
        ("sonarr", 8989, f"{MEDIA_ROOT}/library/tv"),
    ):
        config_path = (
            "/var/lib/radarr/.config/Radarr/config.xml"
            if kind == "radarr"
            else "/var/lib/sonarr/.config/NzbDrone/config.xml"
        )
        arr_config = ET.parse(config_path).getroot()
        api_key = arr_config.findtext("ApiKey")
        profiles = arr_request(port, api_key, "qualityprofile")
        profile = profiles[0]
        settings = {
            "name": kind.capitalize(),
            "hostname": "127.0.0.1",
            "port": port,
            "apiKey": api_key,
            "useSsl": False,
            "baseUrl": "",
            "activeProfileId": profile["id"],
            "activeProfileName": profile["name"],
            "activeDirectory": root,
            "tags": [],
            "is4k": False,
            "isDefault": True,
            "externalUrl": f"https://{kind}.outworld66.ru",
            "syncEnabled": True,
            "preventSearch": False,
            "tagRequests": False,
            "overrideRule": [],
        }
        response = seerr_request(
            f"/api/v1/settings/{kind}/test",
            method="POST",
            data=settings,
            cookies=cookies,
        )
        if kind == "radarr":
            settings["minimumAvailability"] = "released"
        else:
            settings.update(
                {
                    "seriesType": "standard",
                    "animeSeriesType": "standard",
                    "enableSeasonFolders": True,
                    "monitorNewItems": "all",
                }
            )
        settings["activeProfileId"] = response["profiles"][0]["id"]
        settings["activeProfileName"] = response["profiles"][0]["name"]
        directories = {folder["path"] for folder in response["rootFolders"]}
        if root not in directories:
            raise RuntimeError(f"{kind} root folder is missing")
        current = seerr_request(f"/api/v1/settings/{kind}", cookies=cookies)
        existing = next((item for item in current if item["hostname"] == "127.0.0.1"), None)
        if existing:
            seerr_request(
                f"/api/v1/settings/{kind}/{existing['id']}",
                method="PUT",
                data=settings,
                cookies=cookies,
            )
        else:
            seerr_request(
                f"/api/v1/settings/{kind}", method="POST", data=settings, cookies=cookies
            )

    public = seerr_request("/api/v1/settings/public", cookies=cookies)
    if not public.get("initialized"):
        seerr_request("/api/v1/settings/initialize", method="POST", cookies=cookies)
    print("Seerr Jellyfin, Radarr, and Sonarr connections are configured")
    return restart_after_configure


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
    configure_arr(7878, "/var/lib/radarr/.config/Radarr", f"{MEDIA_ROOT}/library/movies", "movies")
    configure_arr(8989, "/var/lib/sonarr/.config/NzbDrone", f"{MEDIA_ROOT}/library/tv", "tv", [5000])
    configure_jellyfin()
    restart_seerr = configure_seerr()
    configure_bindery()
    if restart_seerr:
        subprocess.run(["systemctl", "restart", "seerr.service"], check=True)


if __name__ == "__main__":
    main()

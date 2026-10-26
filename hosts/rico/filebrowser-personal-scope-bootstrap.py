#!/usr/bin/env python3
import json
import os
import shutil
import sqlite3
import sys
from pathlib import Path, PurePosixPath


def main() -> None:
    (
        database_path,
        users_path,
        source_path,
        old_source_path,
        old_users_path,
    ) = map(Path, sys.argv[1:6])
    media_source_path = sys.argv[6]
    users_path.mkdir(mode=0o750, parents=True, exist_ok=True)
    old_users_path.mkdir(mode=0o750, parents=True, exist_ok=True)
    connection = sqlite3.connect(database_path)
    try:
        rows = connection.execute(
            "SELECT username, perm_admin, user_data FROM users"
        ).fetchall()
        usernames = {row[0] for row in rows}
        updates = []
        for username, is_admin, raw_data in rows:
            if not username or username in {".", ".."} or "/" in username:
                raise ValueError(f"Unsafe File Browser username: {username!r}")

            user_data = json.loads(raw_data)
            original_data = json.loads(raw_data)
            scopes = user_data.setdefault("backendScopes", [])
            personal_scopes = [
                scope
                for scope in scopes
                if scope.get("path") in {str(source_path), str(old_source_path)}
            ]
            if len(personal_scopes) > 1:
                raise ValueError(f"Duplicate personal scopes for {username!r}")
            if personal_scopes:
                personal_scopes[0]["path"] = str(source_path)
                if not is_admin:
                    personal_scopes[0]["scope"] = f"/{username}"
            elif not is_admin:
                scopes.append(
                    {
                        "path": str(source_path),
                        "scope": f"/{username}",
                        "permissions": {
                            "configured": True,
                            "view": True,
                            "download": True,
                            "modify": True,
                            "create": True,
                            "delete": True,
                        },
                    }
                )

            source_permissions = user_data.get("backendSourcePermissions", {})
            if str(old_source_path) in source_permissions:
                source_permissions[str(source_path)] = source_permissions.pop(
                    str(old_source_path)
                )

            sidebar_links = user_data.get("settings", {}).get("sidebarLinks", [])
            for link in sidebar_links:
                if link.get("sourceName") == str(old_source_path):
                    link["sourceName"] = str(source_path)

            if user_data != original_data:
                updates.append((json.dumps(user_data), username))

            user_dir = users_path / username
            user_dir.mkdir(mode=0o750, exist_ok=True)
            os.chmod(user_dir, 0o750)
            os.chown(user_dir, 2002, 2000)

        file_owners = {}
        for username, path in connection.execute(
            """
            SELECT users.username, activity_log.path
            FROM activity_log JOIN users USING (user_id)
            WHERE activity_log.success = 1
              AND activity_log.source = 'Personal files'
              AND activity_log.event_type IN ('upload', 'create', 'mkdir')
            """
        ):
            if path:
                parts = PurePosixPath(path.lstrip("/")).parts
                if parts:
                    file_owners.setdefault(parts[0], set()).add(username)

        for old_item in old_users_path.iterdir():
            owners = file_owners.get(old_item.name, set())
            if len(owners) != 1 or not owners <= usernames:
                raise ValueError("Cannot safely identify owner of an existing personal file")
            owner = next(iter(owners))
            destination = users_path / owner / old_item.name
            if destination.exists():
                raise FileExistsError("Personal file migration destination already exists")
            shutil.move(str(old_item), str(destination))

        expected_rule = json.dumps(
            {
                "Deny": {"Users": {}, "Groups": {}},
                "Allow": {
                    "Users": {},
                    "Groups": {"media-admin": {}, "media-user": {}},
                },
            },
            separators=(",", ":"),
        ).encode()
        current_rule = connection.execute(
            "SELECT rule_data FROM access_rules WHERE source = ? AND path = ?",
            (media_source_path, "/"),
        ).fetchone()
        rule_changed = current_rule is None or current_rule[0] != expected_rule

        if updates or rule_changed:
            backup_path = database_path.with_name(
                "filebrowser.sqlite.before-personal-scope"
            )
            if not backup_path.exists():
                os.umask(0o077)
                backup = sqlite3.connect(backup_path)
                try:
                    connection.backup(backup)
                finally:
                    backup.close()
                os.chmod(backup_path, 0o600)
            with connection:
                connection.executemany(
                    "UPDATE users SET user_data = ? WHERE username = ?", updates
                )
                connection.execute(
                    """
                    INSERT INTO access_rules (source, path, rule_data)
                    VALUES (?, '/', ?)
                    ON CONFLICT(source, path)
                    DO UPDATE SET rule_data = excluded.rule_data
                    """,
                    (media_source_path, sqlite3.Binary(expected_rule)),
                )
    finally:
        connection.close()


if __name__ == "__main__":
    main()

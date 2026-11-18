#!/usr/bin/env python3
"""Upgrade sync-test SQLite fixtures to the current Neuron chain schema."""

from __future__ import annotations

import argparse
import hashlib
import shutil
import sqlite3
from pathlib import Path


LEGACY_MULTISIG_CODE_HASH = "0x5c5069eb0857efc65e1bca0c07df34c31663b3622fd3876c876320fc9634e2a8"
XUDT_CODE_HASH = "0xadc42596631d13efbc397c23274ea040bbe879580e13692bdfd91a4275bff136"
MIGRATIONS = (
    (1716539079505, "AddStartBlockNumber1716539079505"),
    (1720089814860, "AddUdtType1720089814860"),
    (1744960856059, "AddLockCodeHash1744960856059"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in connection.execute(f'PRAGMA table_info("{table}")')}


def add_migration(connection: sqlite3.Connection, timestamp: int, name: str) -> None:
    connection.execute(
        "INSERT INTO migrations(timestamp, name) "
        "SELECT ?, ? WHERE NOT EXISTS (SELECT 1 FROM migrations WHERE timestamp = ?)",
        (timestamp, name, timestamp),
    )


def upgrade(path: Path) -> None:
    connection = sqlite3.connect(path)
    try:
        if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError(f"integrity check failed before update: {path}")

        with connection:
            if "startBlockNumber" not in columns(connection, "multisig_config"):
                connection.execute('ALTER TABLE "multisig_config" ADD COLUMN "startBlockNumber" integer')
            add_migration(connection, *MIGRATIONS[0])

            if "udtType" not in columns(connection, "sudt_token_info"):
                connection.execute('ALTER TABLE "sudt_token_info" ADD COLUMN "udtType" varchar')
            connection.execute(
                'CREATE UNIQUE INDEX IF NOT EXISTS "IDX_37bb4f2a4a849bf0b1dadee2c7" '
                'ON "sudt_token_info" ("tokenID", "udtType")'
            )

            xudt_token_ids = {
                row[0]
                for row in connection.execute(
                    'SELECT DISTINCT "typeArgs" FROM "output" WHERE "typeCodeHash" = ?', (XUDT_CODE_HASH,)
                )
                if row[0]
            }
            placeholders = ", ".join("?" for _ in xudt_token_ids)
            xudt_filter = f' AND "tokenID" NOT IN ({placeholders})' if xudt_token_ids else ""
            connection.execute(
                f'UPDATE "sudt_token_info" SET "udtType" = \'sUDT\' '
                f'WHERE "tokenID" != \'CKBytes\' AND "udtType" IS NOT \'sUDT\'{xudt_filter}',
                tuple(xudt_token_ids),
            )

            if "udtType" not in columns(connection, "asset_account"):
                connection.execute('ALTER TABLE "asset_account" ADD COLUMN "udtType" varchar')
            connection.execute(
                'CREATE UNIQUE INDEX IF NOT EXISTS "IDX_5139df6b311e63ecdd93cd17ed" '
                'ON "asset_account" ("tokenID", "blake160", "udtType")'
            )
            connection.execute(
                f'UPDATE "asset_account" SET "udtType" = \'sUDT\' '
                f'WHERE "tokenID" != \'CKBytes\' AND "udtType" IS NOT \'sUDT\'{xudt_filter}',
                tuple(xudt_token_ids),
            )
            for token_id in xudt_token_ids:
                connection.execute(
                    'UPDATE "sudt_token_info" SET "udtType" = \'xUDT\' '
                    'WHERE "tokenID" = ? AND "udtType" IS NOT \'xUDT\'',
                    (token_id,),
                )
                connection.execute(
                    'UPDATE "asset_account" SET "udtType" = \'xUDT\' '
                    'WHERE "tokenID" = ? AND "udtType" IS NOT \'xUDT\'',
                    (token_id,),
                )
            add_migration(connection, *MIGRATIONS[1])

            if "lockCodeHash" not in columns(connection, "multisig_config"):
                connection.execute('ALTER TABLE "multisig_config" ADD COLUMN "lockCodeHash" varchar')
            connection.execute(
                'UPDATE "multisig_config" SET "lockCodeHash" = ? WHERE "lockCodeHash" IS NULL',
                (LEGACY_MULTISIG_CODE_HASH,),
            )
            add_migration(connection, *MIGRATIONS[2])

        if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError(f"integrity check failed after update: {path}")
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path, help="sync-test source/data directory")
    parser.add_argument("--backup-dir", type=Path, help="directory for byte-for-byte originals")
    args = parser.parse_args()
    root = args.root.resolve()
    fixtures = sorted(root.glob("**/*.sqlite"))
    if not fixtures:
        parser.error(f"no SQLite fixtures found under {root}")

    for fixture in fixtures:
        relative = fixture.relative_to(root)
        before = sha256(fixture)
        if args.backup_dir:
            backup = args.backup_dir.resolve() / relative
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(fixture, backup)
        upgrade(fixture)
        print(f"UPDATED {relative} sha256:{before} -> {sha256(fixture)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

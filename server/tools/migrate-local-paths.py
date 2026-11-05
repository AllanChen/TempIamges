#!/usr/bin/env python3
"""Repair local Widget registration paths after the 2026-10 repository move.

Dry-run by default. --apply creates a SQLite backup before updating only paths.
No API calls, task execution, price changes, or registration-state changes.
"""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import sqlite3


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, default=Path.home() / '.config/glance/widgets.sqlite')
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    database = args.database.resolve()
    old_root = str(args.repo.resolve() / 'widgets') + '/'
    new_root = str(args.repo.resolve() / 'server/widgets') + '/'
    connection = sqlite3.connect(database.as_uri() + '?mode=ro', uri=True)
    connection.row_factory = sqlite3.Row
    changes = []
    skipped = []
    for row in connection.execute('SELECT * FROM widgets'):
        for column in ('manifest_path', 'code_path', 'python_path'):
            value = row[column]
            if not value or not value.startswith(old_root):
                continue
            replacement = new_root + value[len(old_root):]
            if not Path(replacement).exists():
                skipped.append((row['widget_id'], row['version'], column))
                continue
            changes.append((column, replacement, row['widget_id'], row['version'], value))
    print(f'Path fields to migrate: {len(changes)}; missing targets skipped: {len(skipped)}')
    for widget_id, version, column in skipped:
        print(f'Unresolved existing registration: {widget_id} {version} {column}')
    if args.apply and changes:
        suffix = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        backup = database.with_name(database.name + '.before-reorganization-' + suffix + '.bak')
        backup.touch(mode=0o600, exist_ok=False)
        with sqlite3.connect(backup) as target:
            connection.backup(target)
        connection.close()
        with sqlite3.connect(database) as writable:
            for column, replacement, widget_id, version, previous in changes:
                # column is selected exclusively from the constant list above.
                writable.execute(
                    f'UPDATE widgets SET {column}=? WHERE widget_id=? AND version=? AND {column}=?',
                    (replacement, widget_id, version, previous),
                )
        print(f'Applied path updates. Backup: {backup}')
    else:
        connection.close()
        print('No changes made.' if not args.apply else 'No remaining migratable paths.')


if __name__ == '__main__':
    main()

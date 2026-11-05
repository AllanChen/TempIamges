#!/usr/bin/env python3
"""Refresh the public, build-time Widget and pricing snapshot from the live API."""
from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TARGET = ROOT / "src" / "public-snapshot.json"
API = "https://api.glancepreview.com/api/v2"


def fetch(path: str) -> dict:
    response = subprocess.run(
        ["curl", "-fsSL", "--max-time", "20", f"{API}{path}"],
        capture_output=True, text=True,
    )
    if response.returncode:
        raise SystemExit(f"Could not refresh {path}: {response.stderr.strip()}")
    body = json.loads(response.stdout)
    if body.get("success") is not True or not isinstance(body.get("result"), dict):
        raise ValueError(f"Unexpected public API response for {path}")
    return body["result"]


def main() -> None:
    catalog = fetch("/widgets?limit=50")
    pricing = fetch("/pricing")
    if not isinstance(catalog.get("widgets"), list) or not isinstance(pricing.get("proTiers"), list):
        raise SystemExit("Public API is missing its Widget or pricing catalog; snapshot was not updated")
    widgets = []
    for widget in catalog.get("widgets", []):
        if not widget.get("name") or widget["name"] == "My Widget":
            continue
        english = (widget.get("localizations") or {}).get("en") or {}
        widgets.append({
            "id": widget["id"],
            "name": widget["name"],
            "summary": widget.get("summary") or "",
            "enName": english.get("name") or widget["name"],
            "enSummary": english.get("summary") or widget.get("summary") or "",
            "creditCost": widget.get("creditCost", 1),
            "billing": widget.get("billing") or {},
            "uploadsMedia": bool((widget.get("privacy") or {}).get("uploadsMedia")),
        })
    public_pricing = {key: pricing.get(key) for key in (
        "enabled", "paymentsAvailable", "trialDays", "signupCredits",
        "proBonusCredits", "launchUntil", "defaultCurrency", "proTiers", "packs",
    )}
    snapshot = {
        "fetchedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "widgets": widgets,
        "pricing": public_pricing,
    }
    TARGET.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {len(widgets)} public Widgets and pricing state to {TARGET}")


if __name__ == "__main__":
    main()

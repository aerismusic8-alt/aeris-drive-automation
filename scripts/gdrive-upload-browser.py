#!/usr/bin/env python3
"""Upload to Google Drive through the signed-in cloud desktop browser.

This is the fallback for when the Drive API is not available: the OAuth client
this project owns belongs to a Cloud project where the Drive API is disabled, and
the account cannot enable it (no IAM access to that project). The browser needs
no API at all -- it is the same upload a human does by hand.

The desktop is a singleton and its login is the credential, so the browser must
already be signed in (see `.agents/skills/ax-cloud-desktop`).

    python3 scripts/gdrive-upload-browser.py --folder "AX Content Lab/aeris938-1" \
        --glob 'aeris938-1/work/*/*.mp4' aeris938-1/library/episodes.json

A batch is one "New > File upload" with several files selected; Drive queues
them. `--batch` tunes how many files per chooser call.
"""
from __future__ import annotations

import argparse
import glob as globmod
import re
import sys
import time
from pathlib import Path

CDP = "http://127.0.0.1:9222"
DRIVE = "https://drive.google.com/drive/my-drive"
NEW_BUTTON = "[guidedhelpid='new_menu_button']"


def connect(pw):
    browser = pw.chromium.connect_over_cdp(CDP)
    if not browser.contexts:
        raise SystemExit("no browser context on the desktop; is chromium up?")
    page = browser.contexts[0].new_page()
    return browser, page


def open_drive(page):
    page.goto(DRIVE, wait_until="load", timeout=120_000)
    page.wait_for_selector(NEW_BUTTON, timeout=60_000, state="visible")
    page.wait_for_timeout(1500)


def menu_item(page, needle: str):
    """Open New and return the locator whose label contains `needle`."""
    for attempt in range(3):
        try:
            page.wait_for_selector(NEW_BUTTON, timeout=20_000, state="visible")
            page.click(NEW_BUTTON)
            page.wait_for_timeout(1500)
            items = page.locator("[role='menuitem']")
            for i in range(items.count()):
                try:
                    if needle in items.nth(i).inner_text():
                        return items.nth(i)
                except Exception:
                    continue
            return None
        except Exception:
            # Drive's SPA sometimes drops the button after a heavy upload; reload.
            page.wait_for_timeout(3000)
            try:
                page.reload(wait_until="load", timeout=90_000)
            except Exception:
                page.goto(DRIVE, wait_until="load", timeout=90_000)
            page.wait_for_timeout(4000)
    return None


def folder_file_names(page) -> set[str]:
    """Names currently listed in the open folder."""
    try:
        text = page.inner_text("[role='main']")
    except Exception:
        text = page.inner_text("body")
    return set(re.findall(r"[\w\-. ]+\.(?:mp4|json|mp3|png|jpg)", text))


def current_folder_id(page) -> str | None:
    m = re.search(r"/folders/([\w-]+)", page.url)
    return m.group(1) if m else None



def _enter(page, part: str) -> bool:
    """Double-click the folder row named `part`. Several locator shapes, because
    Drive's aria-labels and its visible text do not always agree."""
    for loc in (
        lambda: page.locator(f"[role='main'] [aria-label='{part}']").first,
        lambda: page.get_by_role("gridcell", name=part, exact=True).first,
        lambda: page.get_by_text(part, exact=True).first,
    ):
        try:
            el = loc()
            if el.count() == 0:
                continue
            el.dblclick(timeout=8000)
            page.wait_for_timeout(3000)
            return True
        except Exception:
            continue
    return False


def resolve_folder(page, path: str) -> None:
    """Navigate into a Drive folder path like 'A/B/C', creating what is missing.

    Walking in matters: an upload goes to whatever folder is open, so creating a
    folder without entering it drops every file at My Drive's root instead.
    """
    for part in [p for p in path.split("/") if p]:
        if _enter(page, part):
            continue
        item = menu_item(page, "โฟลเดอร์ใหม่") or menu_item(page, "New folder")
        if item is None:
            item = menu_item(page, "โฟลเดอร์") or menu_item(page, "Folder")
        if item is None:
            raise SystemExit(f"cannot create folder {part!r}: no New-folder menu item")
        item.click()
        page.wait_for_timeout(2500)
        page.keyboard.type(part)
        page.wait_for_timeout(800)
        for sel in ["button:has-text('สร้าง')", "button:has-text('Create')",
                    "button:has-text('ตกลง')", "button:has-text('OK')"]:
            try:
                page.click(sel, timeout=4000)
                break
            except Exception:
                continue
        page.wait_for_timeout(4000)
        if not _enter(page, part):
            raise SystemExit(f"created {part!r} but could not enter it")




def upload_batch(page, files: list[Path]) -> bool:
    item = menu_item(page, "อัปโหลดไฟล์") or menu_item(page, "File upload")
    if item is None:
        print("  ! could not find the File upload menu item", file=sys.stderr)
        return False
    try:
        with page.expect_file_chooser(timeout=30_000) as fc:
            item.click()
        fc.value.set_files([str(f) for f in files])
        return True
    except Exception as exc:
        print(f"  ! chooser failed: {str(exc)[:100]}", file=sys.stderr)
        return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--glob", action="append", default=[])
    ap.add_argument("--folder", default="", help="Drive folder path to upload into")
    ap.add_argument("--batch", type=int, default=12, help="files per upload action")
    ap.add_argument("--settle", type=int, default=35, help="seconds to wait after a batch")
    ap.add_argument("--resume", action="store_true",
                    help="skip files already present in the open folder")
    args = ap.parse_args()

    targets = [Path(f) for f in args.files]
    for g in args.glob:
        targets += sorted(Path(p) for p in globmod.glob(g))
    targets = [t for t in targets if t.is_file()]
    if not targets:
        print("nothing to upload", file=sys.stderr)
        return 1

    from playwright.sync_api import sync_playwright
    with sync_playwright() as pw:
        browser, page = connect(pw)
        open_drive(page)
        if args.folder:
            print(f"folder: {args.folder}")
            resolve_folder(page, args.folder)
            folder_id = current_folder_id(page)
            print(f"  open folder id: {folder_id}")

        if args.resume:
            present = folder_file_names(page)
            before = len(targets)
            targets = [t for t in targets if t.name not in present]
            print(f"resume: {before - len(targets)} already there, {len(targets)} to go")

        total_mb = sum(t.stat().st_size for t in targets) / 1048576
        print(f"{len(targets)} files, {total_mb:.1f} MB, batch={args.batch}")

        sent = failed = 0
        for i in range(0, len(targets), args.batch):
            batch = targets[i:i + args.batch]
            print(f"  batch {i // args.batch + 1}: {len(batch)} files "
                  f"({batch[0].name} ... {batch[-1].name})", flush=True)
            if upload_batch(page, batch):
                sent += len(batch)
            else:
                failed += len(batch)
            page.wait_for_timeout(args.settle * 1000)
        print(f"queued={sent}/{len(targets)} failed={failed}")
        page.close()
    return 0



if __name__ == "__main__":
    raise SystemExit(main())

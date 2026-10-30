#!/usr/bin/env python3
"""Read and drive a Windows app on PC1 through UI Automation.

Chrome exposes its page to UI Automation, so this is how a web app on PC1 is
read as text and clicked by real coordinates. It also returns each element's
centre, which is what makes a click land on the control rather than near it.

    python3 ops/pc1_uia.py dump OpenHands
    python3 ops/pc1_uia.py dump OpenHands --all
    python3 ops/pc1_uia.py click OpenHands "Open Repository"
    python3 ops/pc1_uia.py clicktype OpenHands "Search" "hello" --enter

OCR is not an option on PC1 (tesseract is absent), so this is the text route.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import re
import sys

# Chrome's own frame, which is noise when the point is the page inside it.
NOISE = re.compile(
    r"Minimize|Restore|^Close$|^Back$|^Forward$|^Reload$|Address and search bar"
    r"|Bookmark this tab|^Extensions$|Infobar|Turn off in settings|Tab search"
    r"|^New Tab$|Open Gemini|hidden bookmarks|^Chrome$|^Tab groups$"
    r"|Chrome is being controlled")

PS = r'''
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$cond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::Window)
$wins = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,$cond)
$target = $null
foreach($w in $wins){ if($w.Current.Name -like '*__TITLE__*'){ $target = $w; break } }
if($null -eq $target){ Write-Host 'NO_WINDOW'; exit }
Write-Host "WINDOW=$($target.Current.Name)"
$all = $target.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
$i = 0
foreach($e in $all){
  $n = $e.Current.Name
  if($n -and $n.Trim().Length -gt 0){
    $ct = $e.Current.ControlType.ProgrammaticName.Replace('ControlType.','')
    $r = $e.Current.BoundingRectangle
    $cx = [int]($r.X + $r.Width/2); $cy = [int]($r.Y + $r.Height/2)
    $safe = ($n -replace '\|','/') -replace "`r?`n",' '
    Write-Host "E|$i|$ct|$safe|$cx,$cy|$([int]$r.Width)x$([int]$r.Height)"
    $i++
  }
}
'''


def load():
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("pc1_live", os.path.join(here, "pc1_live.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def dump(p, title):
    ps = PS.replace("__TITLE__", title.replace("'", "''"))
    p.call("FileWrite", {"path": "C:/AX-Runtime/evidence/axuia.ps1", "content": ps})
    r = p.call("Shell", {"command": "powershell -NoProfile -ExecutionPolicy Bypass "
                                    "-File C:/AX-Runtime/evidence/axuia.ps1"})
    txt = "".join(i.get("text", "") for i in (r.get("content") or []) if i.get("type") == "text")
    win, els = None, []
    for line in txt.splitlines():
        line = line.strip()
        if line.startswith("WINDOW="):
            win = line[7:]
        elif line.startswith("E|"):
            parts = line.split("|")
            if len(parts) >= 6:
                try:
                    x, y = [int(v) for v in parts[4].split(",")]
                except ValueError:
                    continue
                els.append({"idx": int(parts[1]), "ct": parts[2], "name": parts[3],
                            "x": x, "y": y, "size": parts[5]})
    return win, els


def show(win, els, everything=False):
    print("WINDOW:", win)
    for e in els:
        if not everything and (e["y"] < 130 or NOISE.search(e["name"])):
            continue
        print(f'  {e["idx"]:4} {e["ct"]:10} {e["name"][:78]:78} ({e["x"]},{e["y"]})')


def main():
    ap = argparse.ArgumentParser(description="Read and click a PC1 app via UI Automation.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("dump")
    d.add_argument("title")
    d.add_argument("--all", action="store_true")
    c = sub.add_parser("click")
    c.add_argument("title")
    c.add_argument("pattern")
    c.add_argument("--index", type=int, default=0)
    t = sub.add_parser("clicktype")
    t.add_argument("title")
    t.add_argument("pattern")
    t.add_argument("text")
    t.add_argument("--enter", action="store_true")
    a = ap.parse_args()

    m = load()
    p = m.PC1().connect()
    win, els = dump(p, a.title)
    if a.cmd == "dump":
        show(win, els, a.all)
        return 0
    hits = [e for e in els if re.search(a.pattern, e["name"], re.I)]
    if not hits:
        print("no element matches", a.pattern)
        return 1
    e = hits[a.index] if a.cmd == "click" else hits[0]
    print(f'clicking "{e["name"][:60]}" at ({e["x"]},{e["y"]})')
    p.call("Click", {"x": e["x"], "y": e["y"]})
    if a.cmd == "clicktype":
        args = {"text": a.text}
        if a.enter:
            args["press_enter"] = True
        print(p.call("Type", args))
    return 0


if __name__ == "__main__":
    sys.exit(main())

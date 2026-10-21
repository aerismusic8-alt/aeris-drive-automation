#!/usr/bin/env bash
# Prove the axvision suite can fail. A test that has never been seen red is not
# evidence; the Luau CLI exit-code trap in this repo is exactly that lesson.
set -u
cd "$(dirname "$0")/.."
cp axvision/signature.py /tmp/sig.bak
cp axvision/state.py /tmp/state.bak
cp axvision/engine.py /tmp/engine.bak
cp axvision/capture.py /tmp/capture.bak

count() { python3 tests/test_axvision.py 2>&1 | grep -cE "^(FAIL|ERROR):" ; }

echo "=== MUTATION 1: distinct_colours counts samples, not colours ==="
python3 - <<'PY'
p='axvision/signature.py'; s=open(p).read()
s=s.replace("return int(np.unique(_packed_sample(frame, step)).size)","return int(_packed_sample(frame, step).size)")
open(p,'w').write(s)
PY
echo "failures: $(count)"
cp /tmp/sig.bak axvision/signature.py

echo "=== MUTATION 2: black threshold raised so a dead screen reads as menu ==="
python3 - <<'PY'
p='axvision/state.py'; s=open(p).read()
s=s.replace("BLACK_DARK_SHARE = 0.97","BLACK_DARK_SHARE = 1.01")
open(p,'w').write(s)
PY
echo "failures: $(count)"
cp /tmp/state.bak axvision/state.py

echo "=== MUTATION 3: engine reports frame coords, not screen coords ==="
python3 - <<'PY'
p='axvision/engine.py'; s=open(p).read()
s=s.replace("return (box[0] * s + self.rect[0], box[1] * s + self.rect[1], box[2] * s, box[3] * s)","return (box[0] * s, box[1] * s, box[2] * s, box[3] * s)")
open(p,'w').write(s)
PY
echo "failures: $(count)"
cp /tmp/engine.bak axvision/engine.py

echo "=== MUTATION 4: downscale removed, so full-HD frames are kept ==="
python3 - <<'PY'
p='axvision/engine.py'; s=open(p).read()
s=s.replace("pixels, factor = signature.downscale(pixels, self.analysis_width)","pixels, factor = pixels, 1")
open(p,'w').write(s)
PY
echo "failures: $(count)"
cp /tmp/engine.bak axvision/engine.py

echo "=== MUTATION 5: change detector treats every pixel as changed ==="
python3 - <<'PY'
p='axvision/signature.py'; s=open(p).read()
s=s.replace("return (np.maximum(a, b) - np.minimum(a, b)).max(axis=2) > threshold","return (np.maximum(a, b) - np.minimum(a, b)).max(axis=2) >= 0")
open(p,'w').write(s)
PY
echo "failures: $(count)"
cp /tmp/sig.bak axvision/signature.py

echo "=== MUTATION 6: frozen detection removed ==="
python3 - <<'PY'
p='axvision/engine.py'; s=open(p).read()
s=s.replace("            if self._still_since is None:\n                self._still_since = now","            self._still_since = None")
open(p,'w').write(s)
PY
echo "failures: $(count)"
cp /tmp/engine.bak axvision/engine.py

echo "=== MUTATION 7: window filtered by title again, so a browser wins ==="
python3 - <<'PY'
p='axvision/capture.py'; s=open(p).read()
s=s.replace("        if name not in (GAME_PROCESS.lower(), STUDIO_PROCESS.lower()):\n            continue",
            "        if 'roblox' not in _title.lower():\n            continue")
open(p,'w').write(s)
PY
echo "failures: $(count)"
cp /tmp/capture.bak axvision/capture.py

echo "=== MUTATION 8: largest-window tiebreak removed, so a 1px strip wins ==="
python3 - <<'PY'
p='axvision/capture.py'; s=open(p).read()
s=s.replace("        key = (rank, area)","        key = (rank, 0)")
open(p,'w').write(s)
PY
echo "failures: $(count)"
cp /tmp/capture.bak axvision/capture.py

echo "=== MUTATION 9: Studio fallback removed, so Play mode reads nothing ==="
python3 - <<'PY'
p='axvision/capture.py'; s=open(p).read()
s=s.replace("        if name not in (GAME_PROCESS.lower(), STUDIO_PROCESS.lower()):",
            "        if name != GAME_PROCESS.lower():")
open(p,'w').write(s)
PY
echo "failures: $(count)"
cp /tmp/capture.bak axvision/capture.py

echo "=== restored: expect 0 failures ==="
echo "failures: $(count)"

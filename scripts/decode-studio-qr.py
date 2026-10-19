#!/usr/bin/env python3
"""Print the Quick Sign-In code from a Studio sign-in screenshot.

Studio paints a QR encoding a Roblox cross-device URL that carries the code.
The capture is a fixed crop of a 1600x900 screen, so the QR sits at a stable
offset; read that window plus the full frame, at a few scales and binarizers.
"""
import re
import sys

import cv2
import zxingcpp

BINARIZERS = (
    zxingcpp.Binarizer.FixedThreshold,
    zxingcpp.Binarizer.LocalAverage,
)

# The code window inside the captured crop, as a fraction of width and height.
WINDOW = (0.22, 0.12, 0.55, 0.57)


def code_from(path: str) -> str | None:
    image = cv2.imread(path)
    if image is None:
        return None

    height, width = image.shape[:2]
    left, top, right, bottom = WINDOW
    window = image[int(height * top):int(height * bottom),
                   int(width * left):int(width * right)]

    for crop in (window, image):
        for scale in (1, 2, 3):
            up = crop if scale == 1 else cv2.resize(
                crop, None, fx=scale, fy=scale, interpolation=cv2.INTER_LINEAR)
            for binarizer in BINARIZERS:
                for result in zxingcpp.read_barcodes(
                        up, formats=zxingcpp.BarcodeFormat.QRCode,
                        binarizer=binarizer):
                    # The URL is percent-encoded, so the code follows code%3D.
                    match = re.search(r"code(?:%3D|=)([A-Za-z0-9]+)", result.text)
                    if match:
                        return match.group(1)
    return None


def main() -> int:
    for path in sys.argv[1:]:
        code = code_from(path)
        if code:
            print(f"QUICK_SIGN_IN_CODE={code}")
            print(f"SHOT={path.rsplit('/', 1)[-1]}")
            return 0
    print("QR_NOT_FOUND")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

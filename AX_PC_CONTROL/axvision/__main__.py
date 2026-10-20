"""Entry point so ``python -m axvision`` works.

``python -m package`` runs ``package.__main__``, not ``package.cli``, so without
this file every documented command fails with "No module named axvision.__main__".
The README and the agent's own instructions both say ``python -m axvision``, so
this is the difference between the tool working and the tool looking broken.
"""

from .cli import main

if __name__ == "__main__":
    raise SystemExit(main())

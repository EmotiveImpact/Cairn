from __future__ import annotations

import sys

from .ui.app import MacSweepApp


def main() -> int:
    if sys.platform != "darwin":
        print("MacSweep is for macOS only.", file=sys.stderr)
        return 1
    app = MacSweepApp()
    app.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

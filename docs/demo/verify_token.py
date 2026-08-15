"""Harmless stdin-only target for the Bubbl README demonstration."""

import sys


EXPECTED_CANARY = "sk-example-7F3A-NOT-A-REAL-KEY"


def main() -> int:
    supplied = sys.stdin.read()
    if supplied == EXPECTED_CANARY:
        print("Demo API authenticated")
        return 0

    print("Demo API rejected the supplied value", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

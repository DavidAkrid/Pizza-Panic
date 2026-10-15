"""Puts temporary checks into scripts/dev_test.gd between its CHECKS markers, or clears them.

  python tools/devtest_checks.py set <host_checks.gd> <client_checks.gd>
  python tools/devtest_checks.py clear

Check files are plain GDScript lines indented with one tab (they run inside _host / _client).
"""
import re
import sys
from pathlib import Path

DEV_TEST = Path(__file__).resolve().parent.parent / "scripts" / "dev_test.gd"


def fill(text, role, lines):
    pattern = re.compile(r"(\t# CHECKS-%s-START\n).*?(\t# CHECKS-%s-END\n)" % (role, role), re.S)
    if not pattern.search(text):
        sys.exit("markers for %s not found in dev_test.gd" % role)
    return pattern.sub(lambda m: m.group(1) + lines + m.group(2), text)


if __name__ == "__main__":
    text = DEV_TEST.read_text(encoding="utf-8")
    if sys.argv[1] == "clear":
        text = fill(fill(text, "HOST", ""), "CLIENT", "")
    elif sys.argv[1] == "set":
        host = Path(sys.argv[2]).read_text(encoding="utf-8").rstrip("\n") + "\n"
        client = Path(sys.argv[3]).read_text(encoding="utf-8").rstrip("\n") + "\n"
        text = fill(fill(text, "HOST", host), "CLIENT", client)
    DEV_TEST.write_text(text, encoding="utf-8")
    print("dev_test.gd checks:", sys.argv[1])

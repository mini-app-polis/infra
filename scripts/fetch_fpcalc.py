#!/usr/bin/env python3
"""Fetch chromaprint's static fpcalc for the fpcalc Lambda layer.

The layer (layers.tf) zips build/fpcalc-layer/, so this runs before
`terraform plan` and `terraform apply`, in CI and on a workstation alike:

    python3 scripts/fetch_fpcalc.py

It downloads the pinned release, refuses it unless its SHA-256 is the one
pinned here, and leaves the binary at build/fpcalc-layer/bin/fpcalc. A Lambda
layer is unpacked under /opt, and /opt/bin is on the function's PATH, so
deejay-cog's fingerprint function finds `fpcalc` there.

The static build decodes audio itself, so no ffmpeg is needed beside it.
Changing the version means changing VERSION and SHA256 together; the layer
is keyed to the binary's own hash, so a new binary publishes a new layer
version and an unchanged one does not.
"""

from __future__ import annotations

import hashlib
import io
import shutil
import sys
import tarfile
import urllib.request
from pathlib import Path

VERSION = "1.6.1"
ARCH = "x86_64"
URL = (
    "https://github.com/acoustid/chromaprint/releases/download/"
    f"v{VERSION}/chromaprint-fpcalc-{VERSION}-linux-{ARCH}.tar.gz"
)
#: SHA-256 of the release archive at URL.
SHA256 = "fc16cd37a70168040bc9ceb45f1d4d1216f5a75bc4c9cf8564bea70ac6a45733"

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "build" / "fpcalc-layer" / "bin" / "fpcalc"


def fetch(url: str = URL) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def extract(archive: bytes, expected_sha256: str = SHA256) -> bytes:
    """The fpcalc binary from the release archive, once its hash is checked."""
    actual = hashlib.sha256(archive).hexdigest()
    if actual != expected_sha256:
        raise SystemExit(
            f"fpcalc archive SHA-256 is {actual}, expected {expected_sha256}. "
            "Refusing to build the layer from it."
        )
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tar:
        for member in tar.getmembers():
            if member.isfile() and Path(member.name).name == "fpcalc":
                handle = tar.extractfile(member)
                if handle is not None:
                    return handle.read()
    raise SystemExit("The release archive has no fpcalc binary.")


def write(binary: bytes, target: Path = TARGET) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".tmp")
    tmp.write_bytes(binary)
    tmp.chmod(0o755)
    shutil.move(tmp, target)


def main() -> int:
    write(extract(fetch()))
    print(f"fpcalc {VERSION} ({ARCH}) at {TARGET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

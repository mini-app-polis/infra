"""scripts/fetch_fpcalc.py without the network: the checksum gate and the extraction.

    python3 -m unittest discover tests
"""

from __future__ import annotations

import hashlib
import io
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import fetch_fpcalc  # noqa: E402

BINARY = b"\x7fELF fake fpcalc"


def release(*members: tuple[str, bytes]) -> bytes:
    """A tar.gz shaped like chromaprint's release archive."""
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tar:
        for name, data in members:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
    return buffer.getvalue()


class ExtractTest(unittest.TestCase):
    def test_returns_the_binary_when_the_hash_matches(self) -> None:
        archive = release(("chromaprint-fpcalc-1.6.1-linux-x86_64/fpcalc", BINARY))
        sha = hashlib.sha256(archive).hexdigest()

        self.assertEqual(fetch_fpcalc.extract(archive, sha), BINARY)

    def test_refuses_an_archive_whose_hash_differs(self) -> None:
        archive = release(("chromaprint-fpcalc-1.6.1-linux-x86_64/fpcalc", BINARY))

        with self.assertRaises(SystemExit) as caught:
            fetch_fpcalc.extract(archive, "0" * 64)
        self.assertIn("Refusing", str(caught.exception))

    def test_refuses_an_archive_with_no_fpcalc(self) -> None:
        archive = release(("chromaprint-fpcalc-1.6.1-linux-x86_64/README", b"x"))
        sha = hashlib.sha256(archive).hexdigest()

        with self.assertRaises(SystemExit):
            fetch_fpcalc.extract(archive, sha)


class WriteTest(unittest.TestCase):
    def test_writes_an_executable_where_the_layer_zips_it(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "fpcalc-layer" / "bin" / "fpcalc"

            fetch_fpcalc.write(BINARY, target)

            self.assertEqual(target.read_bytes(), BINARY)
            self.assertTrue(target.stat().st_mode & 0o111)


class PinTest(unittest.TestCase):
    def test_the_pin_names_a_linux_x86_64_release(self) -> None:
        self.assertIn(f"v{fetch_fpcalc.VERSION}/", fetch_fpcalc.URL)
        self.assertTrue(fetch_fpcalc.URL.endswith("-linux-x86_64.tar.gz"))
        self.assertEqual(len(fetch_fpcalc.SHA256), 64)


if __name__ == "__main__":
    unittest.main()

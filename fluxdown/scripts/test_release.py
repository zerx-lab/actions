import hashlib
from pathlib import Path
import tempfile
import unittest

from release import asset_names, select_release, verify_downloads


def published(version, component="cli"):
    names = [*asset_names(component, version).values(), f"SHA256SUMS-{component}.txt"]
    return {
        "tag_name": f"v{version}", "draft": False, "prerelease": False,
        "assets": [{"name": name, "state": "uploaded"} for name in names],
    }


class ReleaseSelectionTests(unittest.TestCase):
    def test_uses_semantic_version_not_release_order(self):
        releases = [published("0.5.9"), published("0.5.10"), published("0.5.2")]
        self.assertEqual(select_release(releases, "cli")["tag_name"], "v0.5.10")

    def test_skips_prereleases_drafts_and_legacy_component_tags(self):
        prerelease = published("0.6.0")
        prerelease["prerelease"] = True
        draft = published("0.7.0")
        draft["draft"] = True
        legacy = published("0.8.0")
        legacy["tag_name"] = "cli-v0.8.0"
        releases = [published("0.5.3-rc.1"), prerelease, draft, legacy, published("0.5.2")]
        self.assertEqual(select_release(releases, "cli")["tag_name"], "v0.5.2")

    def test_component_missing_from_newer_release_uses_previous_complete_release(self):
        releases = [published("0.5.3", "app"), published("0.5.2")]
        self.assertEqual(select_release(releases, "cli")["tag_name"], "v0.5.2")
        self.assertEqual(select_release(releases, "app")["tag_name"], "v0.5.3")

    def test_explicit_version_never_falls_back(self):
        with self.assertRaises(ValueError):
            select_release([published("0.5.3")], "cli", "0.5.2")
        with self.assertRaises(ValueError):
            select_release([], "cli", "0.5.3-rc.1")

    def test_requires_both_architectures_and_component_checksum(self):
        for missing in range(3):
            release = published("0.5.3")
            release["assets"].pop(missing)
            with self.subTest(missing=missing), self.assertRaises(ValueError):
                select_release([release], "cli", "0.5.3")
        release = published("0.5.3")
        release["assets"][0]["state"] = "new"
        with self.assertRaises(ValueError):
            select_release([release], "cli")

    def test_manual_older_version_is_selected_exactly(self):
        releases = [published("0.5.3"), published("0.5.2")]
        self.assertEqual(select_release(releases, "cli", "0.5.2")["tag_name"], "v0.5.2")


class ChecksumTests(unittest.TestCase):
    def test_verifies_each_architecture_and_rejects_corruption_or_missing_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            lines = []
            expected = {}
            names = asset_names("cli", "0.5.3")
            for arch, name in names.items():
                data = arch.encode()
                (directory / name).write_bytes(data)
                expected[arch] = hashlib.sha256(data).hexdigest()
                lines.append(f"{expected[arch]}  {name}\n")
            manifest = directory / "SHA256SUMS-cli.txt"
            manifest.write_text("".join(lines))
            self.assertEqual(verify_downloads(directory, "cli", "0.5.3"), expected)
            manifest.write_text(lines[0])
            with self.assertRaises(ValueError):
                verify_downloads(directory, "cli", "0.5.3")
            manifest.write_text("".join(lines))
            (directory / names["arm64"]).write_bytes(b"corrupt")
            with self.assertRaises(ValueError):
                verify_downloads(directory, "cli", "0.5.3")

    def test_duplicate_checksum_entry_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            line = "0" * 64 + "  FluxDown-0.5.3-linux-x64.tar.gz\n"
            (directory / "SHA256SUMS-app.txt").write_text(line * 2)
            with self.assertRaises(ValueError):
                verify_downloads(directory, "app", "0.5.3")


if __name__ == "__main__":
    unittest.main()

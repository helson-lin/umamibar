import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cask", Path(__file__).resolve().parents[1] / "scripts/generate-cask.py")
cask = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cask)


class CaskTests(unittest.TestCase):
    def test_release_url_and_checksum(self):
        text = cask.render("helson-lin/umamibar", "1.2.3", "a" * 64)
        self.assertIn('version "1.2.3"', text)
        self.assertIn('sha256 "' + "a" * 64 + '"', text)
        self.assertIn('releases/download/v#{version}/UmamiBar-#{version}-universal.zip', text)
        self.assertIn('app "UmamiBar.app"', text)
        self.assertNotIn("sha256 :no_check", text)

    def test_macos_dependency_avoids_disabled_legacy_versions(self):
        generated = cask.render("helson-lin/umamibar", "1.2.3", "a" * 64)
        published = (Path(__file__).resolve().parents[1] / "Casks/umamibar.rb").read_text()
        for text in (generated, published):
            self.assertIn("depends_on :macos", text)
            self.assertNotIn("catalina", text)
            self.assertNotIn("depends_on macos:", text)

    def test_notarized_release_notice(self):
        text = cask.render("helson-lin/umamibar", "1.2.3", "a" * 64, notarized=True)
        self.assertIn("Developer ID signed and notarized by Apple", text)
        self.assertNotIn("ad-hoc signed", text)

    def test_invalid_release_metadata(self):
        for repo, version, checksum in [("bad", "1.0.0", "a" * 64), ("owner/repo", "v1.0.0", "a" * 64), ("owner/repo", "1.0.0", "missing")]:
            with self.assertRaises(ValueError):
                cask.render(repo, version, checksum)


if __name__ == "__main__":
    unittest.main()

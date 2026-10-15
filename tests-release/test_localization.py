import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDER = re.compile(r"%(?:\.\d+)?(?:ld|@|f|%)")


def source_keys():
    keys = set()
    for path in (ROOT / "Sources/UmamiBar").glob("*.swift"):
        keys.update(re.findall(r'\bL\("((?:[^"\\]|\\.)*)"', path.read_text()))
    return keys


def table(lang):
    # .strings files are old-style plists; plutil converts them for parsing.
    import subprocess
    data = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", str(ROOT / f"Resources/{lang}.lproj/Localizable.strings")], check=True, capture_output=True).stdout
    return plistlib.loads(data)


class LocalizationTests(unittest.TestCase):
    def test_every_ui_string_is_translated(self):
        for lang in ["en", "zh-Hans"]:
            with self.subTest(lang=lang):
                strings = table(lang)
                self.assertEqual(sorted(source_keys() - strings.keys()), [], f"{lang} is missing keys")
                self.assertEqual(sorted(strings.keys() - source_keys()), [], f"{lang} has unused keys")

    def test_placeholders_match(self):
        for key, value in table("en").items():
            with self.subTest(key=key):
                self.assertEqual(PLACEHOLDER.findall(key), PLACEHOLDER.findall(value))


if __name__ == "__main__":
    unittest.main()

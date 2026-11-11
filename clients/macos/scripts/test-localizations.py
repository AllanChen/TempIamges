"""Validate bundled translations without building or launching Glance."""
from pathlib import Path
import json
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1] / "Glance"
LANGUAGES = ("en", "zh-Hans", "ja", "de")


def strings(language):
    path = ROOT / "Resources" / (language + ".lproj") / "Localizable.strings"
    return json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))


class LocalizationTests(unittest.TestCase):
    def test_complete_new_languages_and_format_arguments(self):
        english = strings("en")
        pattern = re.compile(r"%(?:\d+\$)?[-+0 #]*\d*(?:\.\d+)?(?:ll|l|z)?[@diufsg%]")
        for language in ("ja", "de"):
            translated = strings(language)
            self.assertEqual(set(translated), set(english), language)
            for key, value in translated.items():
                with self.subTest(language=language, key=key):
                    self.assertTrue(value.strip())
                    self.assertEqual(pattern.findall(english[key]), pattern.findall(value))

    def test_language_choices_and_bundle_declarations(self):
        preferences = (ROOT / "Sources/Preferences.swift").read_text()
        info = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(ROOT / "Info.plist")]))
        for language in LANGUAGES:
            self.assertIn(language, info["CFBundleLocalizations"])
            self.assertIn('= "' + language + '"', preferences)
            self.assertTrue(strings(language))
        self.assertIn('allCases.map(\\.displayName)', (ROOT / "Sources/PreferencesWindow.swift").read_text())


if __name__ == "__main__":
    unittest.main()

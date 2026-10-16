"""Release security integration checks. Run after Scripts/make-app.sh:
    python3 -m unittest discover -s Scripts/tests -v
Uses only disposable keys; never decrypts the production key or publishes a release.
"""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "build/sparkle-tools/2.10.0/bin"


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], text=True, capture_output=True, **kwargs)


class SignedFeedTests(unittest.TestCase):
    def test_packaged_app_requires_signatures(self):
        with (ROOT / "build/Pullglance.app/Contents/Info.plist").open("rb") as f:
            plist = plistlib.load(f)
        self.assertIs(plist.get("SURequireSignedFeed"), True)
        self.assertIs(plist.get("SUVerifyUpdateBeforeExtraction"), True)
        self.assertEqual(plist.get("SUSignedFeedFailureExpirationInterval"), 0)

    def test_release_check_rejects_missing_security_settings(self):
        with tempfile.TemporaryDirectory() as scratch:
            app = Path(scratch) / "Pullglance.app"
            (app / "Contents").mkdir(parents=True)
            with (ROOT / "build/Pullglance.app/Contents/Info.plist").open("rb") as f:
                plist = plistlib.load(f)
            for setting in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUSignedFeedFailureExpirationInterval"):
                with self.subTest(setting=setting):
                    invalid = dict(plist)
                    invalid.pop(setting, None)
                    with (app / "Contents/Info.plist").open("wb") as f:
                        plistlib.dump(invalid, f)
                    result = run(ROOT / "Scripts/check-app.sh", app, plist["CFBundleVersion"], plist["SUPublicEDKey"])
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn(setting, result.stderr)

    def test_generator_signs_feed_and_embedded_notes(self):
        with tempfile.TemporaryDirectory() as scratch:
            scratch = Path(scratch)
            key = scratch / "key"
            generated = run("swift", ROOT / "Scripts/tests/disposable-key.swift", key)
            self.assertEqual(generated.returncode, 0, generated.stderr)
            pub = generated.stdout.strip()
            app = scratch / "Pullglance.app"
            shutil.copytree(ROOT / "build/Pullglance.app", app, symlinks=True)
            plist_path = app / "Contents/Info.plist"
            with plist_path.open("rb") as f:
                plist = plistlib.load(f)
            plist["SUPublicEDKey"] = pub
            with plist_path.open("wb") as f:
                plistlib.dump(plist, f)
            result = run("codesign", "--force", "--sign", "-", app)
            self.assertEqual(result.returncode, 0, result.stderr)
            archive = scratch / "Pullglance.zip"
            result = run("ditto", "-c", "-k", "--keepParent", app, archive)
            self.assertEqual(result.returncode, 0, result.stderr)
            notes = scratch / "notes.md"
            notes.write_text("Signed rehearsal notes.\n")
            feed = scratch / "appcast.xml"
            result = run(ROOT / "Scripts/make-appcast.sh", "--version", plist["CFBundleVersion"],
                         "--zip", archive, "--notes", notes, "--out", feed,
                         "--public-key", pub, "--key-file", key)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            verified = run(TOOLS / "sign_update", "--ed-key-file", key, "--verify", feed)
            self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)
            self.assertIn("Signed rehearsal notes.", feed.read_text())
            feed.write_bytes(feed.read_bytes().replace(b"Signed rehearsal notes.", b"Forged rehearsal notes."))
            verified = run(TOOLS / "sign_update", "--ed-key-file", key, "--verify", feed)
            self.assertNotEqual(verified.returncode, 0, "tampered notes were accepted")


class StrictVerifierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.scratch.name)
        cls.verifier = cls.directory / "verify-appcast"
        result = run("swiftc", ROOT / "Scripts/verify-appcast.swift", "-o", cls.verifier)
        if result.returncode:
            raise RuntimeError(result.stderr)
        cls.key = cls.directory / "key"
        result = run("swift", ROOT / "Scripts/tests/disposable-key.swift", cls.key)
        if result.returncode:
            raise RuntimeError(result.stderr)
        cls.pub = result.stdout.strip()
        cls.archive = cls.directory / "Pullglance.zip"
        cls.archive.write_bytes(b"signed archive bytes")
        result = run(TOOLS / "sign_update", "--ed-key-file", cls.key, "-p", cls.archive)
        if result.returncode:
            raise RuntimeError(result.stderr)
        cls.signature = result.stdout.strip()
        cls.item = f'''<item><sparkle:version>0.3.0</sparkle:version>
<sparkle:shortVersionString>0.3.0</sparkle:shortVersionString>
<description><![CDATA[Trusted notes]]></description>
<enclosure url="https://github.com/andersonba/pullglance/releases/download/v0.3.0/Pullglance.zip"
length="{cls.archive.stat().st_size}" sparkle:edSignature="{cls.signature}"/></item>'''

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def feed(self, item=None, sign=True):
        path = self.directory / "appcast.xml"
        path.write_text('<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>'
                        + (self.item if item is None else item) + '</channel></rss>')
        if sign:
            result = run(TOOLS / "sign_update", "--ed-key-file", self.key, path)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return path

    def verify(self, path, *extra):
        return run(self.verifier, path, self.archive, self.pub, "0.3.0", *extra)

    def reject(self, path, reason):
        result = self.verify(path)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(reason, result.stderr)

    def test_valid_feed(self):
        result = self.verify(self.feed())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_namespace_alias(self):
        path = self.feed(sign=False)
        path.write_text(path.read_text().replace("xmlns:sparkle=", "xmlns:s=").replace("sparkle:", "s:"))
        signed = run(TOOLS / "sign_update", "--ed-key-file", self.key, path)
        self.assertEqual(signed.returncode, 0, signed.stderr)
        result = self.verify(path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unsigned_feed(self):
        self.reject(self.feed(sign=False), "feed signature")

    def test_tampered_notes(self):
        path = self.feed()
        path.write_bytes(path.read_bytes().replace(b"Trusted notes", b"Untrusted notes"))
        self.reject(path, "feed signature")

    def test_wrong_feed_key(self):
        path = self.feed()
        other_key = self.directory / "other-key"
        generated = run("swift", ROOT / "Scripts/tests/disposable-key.swift", other_key)
        self.assertEqual(generated.returncode, 0, generated.stderr)
        signed = run(TOOLS / "sign_update", "--ed-key-file", other_key, path)
        self.assertEqual(signed.returncode, 0, signed.stderr)
        self.reject(path, "feed signature")

    def test_exactly_one_item(self):
        for item in ("", self.item * 2):
            with self.subTest(item_count=item.count("<item>")):
                self.reject(self.feed(item), "one item")

    def test_versions_must_match(self):
        for tag in ("version", "shortVersionString"):
            with self.subTest(tag=tag):
                self.reject(self.feed(self.item.replace(f"<sparkle:{tag}>0.3.0", f"<sparkle:{tag}>0.2.0")), tag)

    def test_duplicate_or_missing_version(self):
        version = "<sparkle:version>0.3.0</sparkle:version>"
        for replacement in ("", version * 2):
            self.reject(self.feed(self.item.replace(version, replacement)), "version")

    def test_namespace_spoof(self):
        item = self.item.replace("<sparkle:version>", '<sparkle:version xmlns:sparkle="https://attacker.invalid/">')
        self.reject(self.feed(item), "version")

    def test_url_must_match(self):
        for url in ("https://attacker.invalid/Pullglance.zip", "https://github.com/andersonba/pullglance/releases/download/v0.2.0/Pullglance.zip"):
            with self.subTest(url=url):
                self.reject(self.feed(self.item.replace("https://github.com/andersonba/pullglance/releases/download/v0.3.0/Pullglance.zip", url)), "url")

    def test_rehearsal_prefix(self):
        item = self.item.replace("https://github.com/andersonba/pullglance/releases/download/v0.3.0/", "http://127.0.0.1:8765/")
        path = self.feed(item)
        self.reject(path, "url")
        result = self.verify(path, "--download-url-prefix", "http://127.0.0.1:8765/")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_length_must_match(self):
        self.reject(self.feed(self.item.replace(f'length="{self.archive.stat().st_size}"', 'length="1"')), "length")

    def test_exactly_one_enclosure(self):
        enclosure = self.item[self.item.index("<enclosure"):self.item.index("</item>")]
        self.reject(self.feed(self.item.replace(enclosure, enclosure * 2)), "one enclosure")

    def test_bad_archive_signature(self):
        self.reject(self.feed(self.item.replace(self.signature, "A" * 86 + "==")), "archive signature")

    def test_tampered_archive_same_size(self):
        path = self.feed()
        original = self.archive.read_bytes()
        try:
            self.archive.write_bytes(bytes([original[0] ^ 1]) + original[1:])
            self.reject(path, "archive signature")
        finally:
            self.archive.write_bytes(original)

    def test_conflicting_legacy_version_attribute(self):
        self.reject(self.feed(self.item.replace("<enclosure ", '<enclosure sparkle:version="9.9.9" ')), "version")

    def test_unsigned_trailing_content(self):
        path = self.feed()
        path.write_bytes(path.read_bytes() + b"<!-- extra unsigned content -->")
        self.reject(path, "feed signature")

    def test_wrong_feed_length(self):
        path = self.feed()
        data = path.read_bytes()
        start = data.rindex(b"length: ") + len(b"length: ")
        end = data.index(b"\n", start)
        path.write_bytes(data[:start] + b"1" + data[end:])
        self.reject(path, "feed signature")

    def test_malformed_xml(self):
        path = self.feed(sign=False)
        path.write_text(path.read_text().replace("</channel>", ""))
        result = run(TOOLS / "sign_update", "--disable-signing-warning", "--ed-key-file", self.key, path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.reject(path, "XML")


class ReleaseKeyGuardTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.repo = Path(self.scratch.name)
        (self.repo / "Scripts").mkdir()
        shutil.copy(ROOT / "Scripts/release.sh", self.repo / "Scripts/release.sh")
        self.key = "A" * 43 + "="
        self.write_key(self.key)
        (self.repo / "version.env").write_text("VERSION=0.2.0\n")
        for args in (("init", "-b", "main"), ("config", "user.name", "Test"),
                     ("config", "user.email", "test@example.invalid"), ("add", "."),
                     ("commit", "-m", "previous release"), ("tag", "v0.2.0")):
            self.git(*args)
        # If the guard permits proceeding, stop at the first gh call. No network, tag or release mutation.
        (self.repo / "bin").mkdir()
        gh = self.repo / "bin/gh"
        gh.write_text("#!/bin/sh\necho 'REACHED_GH' >&2\nexit 1\n")
        gh.chmod(0o755)
        self.git("add", ".")
        self.git("commit", "-m", "offline sentinel")

    def git(self, *args):
        result = run("git", "-C", self.repo, *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def write_key(self, value):
        (self.repo / "Scripts/make-app.sh").write_text(f'SPARKLE_PUBLIC_KEY="{value}"\nSPARKLE_PUBLIC_KEY="${{PULLGLANCE_REHEARSAL_PUBLIC_KEY:-$SPARKLE_PUBLIC_KEY}}"\n')

    def release(self, *flags):
        env = {k: v for k, v in os.environ.items() if not k.startswith("PULLGLANCE_REHEARSAL_")}
        env["PATH"] = str(self.repo / "bin") + os.pathsep + env["PATH"]
        return run(self.repo / "Scripts/release.sh", "0.3.0", *flags, env=env)

    def change_key(self):
        self.write_key("B" * 43 + "=")
        self.git("add", ".")
        self.git("commit", "-m", "changed key")

    def test_changed_key_blocks_before_network(self):
        self.change_key()
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SPARKLE_PUBLIC_KEY changed since v0.2.0", result.stderr)
        self.assertNotIn("REACHED_GH", result.stderr)
        self.assertEqual(self.git("tag").strip(), "v0.2.0")

    def test_unchanged_key_continues(self):
        result = self.release()
        self.assertIn("gh is not logged in", result.stderr)

    def test_explicit_rotation_flag(self):
        self.change_key()
        result = self.release("--allow-key-rotation")
        self.assertIn("explicit key rotation", result.stderr)
        self.assertIn("gh is not logged in", result.stderr)

    def test_unknown_flag_rejected(self):
        result = self.release("--allow-key-rotaton")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_missing_key_in_previous_tag_blocks(self):
        self.git("show", "v0.2.0:Scripts/make-app.sh")
        (self.repo / "Scripts/make-app.sh").write_text("# missing key\n")
        (self.repo / "version.env").write_text("VERSION=0.2.1\n")
        self.git("add", ".")
        self.git("commit", "-m", "bad release fixture")
        self.git("tag", "v0.2.1")
        self.change_key()
        result = self.release("--allow-key-rotation")
        self.assertIn("cannot read one SPARKLE_PUBLIC_KEY from v0.2.1", result.stderr)

    def test_resume_compares_against_previous_tag(self):
        self.change_key()
        self.git("tag", "v0.3.0")
        result = self.release()
        self.assertIn("SPARKLE_PUBLIC_KEY changed since v0.2.0", result.stderr)


if __name__ == "__main__":
    unittest.main()

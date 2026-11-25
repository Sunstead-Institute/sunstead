import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

MODULE = importlib.util.spec_from_file_location("audit_live", Path(__file__).with_name("audit-live.py"))
audit = importlib.util.module_from_spec(MODULE)
MODULE.loader.exec_module(audit)


def bundle(entries):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w:gz") as tar:
        for name, content in entries:
            item = tarfile.TarInfo(name)
            item.size = len(content)
            tar.addfile(item, io.BytesIO(content))
    return out.getvalue()


class AuditTests(unittest.TestCase):
    def test_archive_ignores_git_and_rejects_paths(self):
        self.assertEqual(audit.archive_files(bundle([(".git/config", b"untrusted"), ("Spec.lean", b"x")])),
                         {"Spec.lean": (b"x", False)})
        for path in ("../outside", "/absolute"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "unsafe archive"):
                audit.archive_files(bundle([(path, b"x")]))

    def test_patch_replay_requires_frozen_and_scoped_changes(self):
        manifest = {"frozen_paths": ["Spec.lean"], "tasks": [
            {"id": "root", "depends_on": [], "target_files": ["Proof.lean"]},
        ]}
        seed = {"Spec.lean": (b"def spec := True\n", False), "Proof.lean": (b"old\n", False)}
        live = {**seed, "Proof.lean": (b"new\n", False)}
        digest = audit.spec_hash(manifest, seed)
        history = [{"seq": 1, "task_id": "root", "spec_sha256": digest}]
        patch = b"""From: Example <example@example.test>
Date: Sat, 1 Jan 2022 00:00:00 +0000
Subject: [PATCH] replace proof

---
diff --git a/Proof.lean b/Proof.lean
--- a/Proof.lean
+++ b/Proof.lean
@@ -1 +1 @@
-old
+new
"""
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            mission = tmp / "mission"
            mission.mkdir()
            for p, (data, _) in seed.items():
                (mission / p).write_bytes(data)
            self.assertEqual(audit.replay(tmp / "pass", mission, manifest, history, patch, seed, live, digest),
                             (["root"], live))
            other = {**live, "Spec.lean": (b"def spec := False\n", False)}
            with self.assertRaisesRegex(ValueError, "frozen hash mismatch"):
                audit.replay(tmp / "frozen", mission, manifest, history, patch, seed, other, digest)
            wrong_scope = {**manifest, "tasks": [{**manifest["tasks"][0], "target_files": ["Other.lean"]}]}
            with self.assertRaisesRegex(ValueError, "unexpected task files"):
                audit.replay(tmp / "scope", mission, wrong_scope, history, patch, seed, live, digest)
            with self.assertRaisesRegex(ValueError, "differs from live bundle"):
                audit.replay(tmp / "different", mission, manifest, history, patch, seed, seed, digest)


if __name__ == "__main__":
    unittest.main()

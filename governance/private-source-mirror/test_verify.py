#!/usr/bin/env python3
"""Contract tests for signed HMG private exact-source mirror provenance."""

from __future__ import annotations

import base64
import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERIFIER = HERE / "verify.py"


def run(
    *args: str,
    cwd: Path | None = None,
    check: bool = True,
    input_bytes: bytes | None = None,
) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(
        list(args),
        cwd=cwd,
        input=input_bytes,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if check and result.returncode != 0:
        output = result.stdout.decode(errors="replace")
        raise AssertionError(f"command failed ({result.returncode}): {' '.join(args)}\n{output}")
    return result


def git(repository: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    return run("git", "-C", str(repository), *args, check=check)


def git_output(repository: Path, *args: str) -> str:
    return git(repository, *args).stdout.decode().strip()


class PrivateSourceMirrorVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.root = Path(self._temp.name)
        self.source = self.root / "source"
        self.target = self.root / "target"
        self.private_key = self.root / "private.pem"
        self.public_key = self.root / "public.pem"
        run("openssl", "genpkey", "-algorithm", "ED25519", "-out", str(self.private_key))
        run(
            "openssl",
            "pkey",
            "-in",
            str(self.private_key),
            "-pubout",
            "-out",
            str(self.public_key),
        )
        public_der = run(
            "openssl",
            "pkey",
            "-pubin",
            "-in",
            str(self.public_key),
            "-outform",
            "DER",
        ).stdout
        self.key_id = f"ed25519-spki-sha256-{hashlib.sha256(public_der).hexdigest()}"

        self._init_repository(self.source)
        self._write_exact_tree(self.source)
        git(self.source, "add", "--all")
        git(self.source, "commit", "-m", "feat(source): establish exact source tree")
        self.source_sha = git_output(self.source, "rev-parse", "HEAD")
        self.source_tree = f"sha1:{git_output(self.source, 'rev-parse', 'HEAD^{tree}')}"

        self._init_repository(self.target)
        self._write_exact_tree(self.target)
        self.target_sha = self._commit_target()

    def tearDown(self) -> None:
        self._temp.cleanup()

    @staticmethod
    def _init_repository(repository: Path) -> None:
        repository.mkdir()
        run("git", "init", "--initial-branch=main", str(repository))
        git(repository, "config", "user.name", "Mirror Contract Test")
        git(repository, "config", "user.email", "mirror-contract@example.invalid")

    @staticmethod
    def _write_exact_tree(repository: Path) -> None:
        (repository / "README.md").write_text("exact private source mirror\n", encoding="utf-8")
        script = repository / "run.sh"
        script.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        script.chmod(0o755)

    def _statement(
        self,
        *,
        source_sha: str,
        source_tree: str,
        export_tree: str,
        workflow_run: str,
        key_id: str,
    ) -> bytes:
        return (
            "\n".join(
                (
                    "HMG-PRIVATE-SOURCE-MIRROR-V1",
                    "source-repository=HMG-AI/HMG",
                    "source-ref=refs/heads/main",
                    f"source-sha={source_sha}",
                    f"source-tree={source_tree}",
                    f"export-tree={export_tree}",
                    f"workflow-run={workflow_run}",
                    "target-repository=HMG-AI/HMG-DEV-brach",
                    "target-branch=main",
                    f"key-id={key_id}",
                )
            )
            + "\n"
        ).encode()

    def _trailers(
        self,
        *,
        source_sha: str | None = None,
        source_tree: str | None = None,
        export_tree: str | None = None,
        workflow_run: str = "https://github.com/HMG-AI/HMG/actions/runs/123456789",
        key_id: str | None = None,
    ) -> list[str]:
        resolved_source_sha = source_sha or self.source_sha
        resolved_source_tree = source_tree or self.source_tree
        resolved_export_tree = export_tree or self.source_tree
        resolved_key_id = key_id or self.key_id
        statement = self._statement(
            source_sha=resolved_source_sha,
            source_tree=resolved_source_tree,
            export_tree=resolved_export_tree,
            workflow_run=workflow_run,
            key_id=resolved_key_id,
        )
        statement_path = self.root / "statement.txt"
        statement_path.write_bytes(statement)
        signature = run(
            "openssl",
            "pkeyutl",
            "-sign",
            "-inkey",
            str(self.private_key),
            "-rawin",
            "-in",
            str(statement_path),
        ).stdout
        return [
            "HMG-Mirror-Contract: HMG-PRIVATE-SOURCE-MIRROR-V1",
            "HMG-Source-Repository: HMG-AI/HMG",
            f"HMG-Source-SHA: {resolved_source_sha}",
            f"HMG-Source-Tree: {resolved_source_tree}",
            f"HMG-Export-Tree: {resolved_export_tree}",
            f"HMG-Workflow-Run: {workflow_run}",
            f"HMG-Provenance-Key-ID: {resolved_key_id}",
            f"HMG-Provenance-Signature-Ed25519: {base64.b64encode(signature).decode()}",
        ]

    def _commit_target(
        self,
        *,
        trailers: list[str] | None = None,
        amend: bool = False,
    ) -> str:
        git(self.target, "add", "--all")
        export_tree = f"sha1:{git_output(self.target, 'write-tree')}"
        governed = trailers or self._trailers(export_tree=export_tree)
        command = ["commit"]
        if amend:
            command.append("--amend")
        command.extend(
            [
                "-m",
                "chore(mirror): import exact HMG source",
                "-m",
                "\n".join(governed),
            ]
        )
        git(self.target, *command)
        return git_output(self.target, "rev-parse", "HEAD")

    def _amend_trailers(self, trailers: list[str]) -> None:
        self.target_sha = self._commit_target(trailers=trailers, amend=True)

    def _verify(
        self,
        *,
        event_name: str = "pull_request",
        public_key: Path | None = None,
    ) -> subprocess.CompletedProcess[bytes]:
        return run(
            "python3",
            str(VERIFIER),
            "--target-repository-dir",
            str(self.target),
            "--target-sha",
            self.target_sha,
            "--event-name",
            event_name,
            "--target-repository",
            "HMG-AI/HMG-DEV-brach",
            "--target-base-ref",
            "main",
            "--trusted-public-key",
            str(public_key or self.public_key),
            check=False,
        )

    def assert_failed(self, result: subprocess.CompletedProcess[bytes], text: str) -> None:
        output = result.stdout.decode(errors="replace")
        self.assertNotEqual(result.returncode, 0, output)
        self.assertIn(text, output)

    def test_exact_signed_source_and_export_tree_pass(self) -> None:
        result = self._verify()
        output = result.stdout.decode()
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("private source mirror verified", output)

    def test_missing_governed_trailer_fails(self) -> None:
        self._amend_trailers(self._trailers()[:-1])
        self.assert_failed(self._verify(), "exactly the eight governed trailers")

    def test_duplicate_governed_trailer_fails(self) -> None:
        trailers = self._trailers()
        trailers.append(trailers[-1])
        self._amend_trailers(trailers)
        self.assert_failed(self._verify(), "exactly the eight governed trailers")

    def test_malformed_source_sha_fails(self) -> None:
        self._amend_trailers(self._trailers(source_sha=self.source_sha.upper()))
        self.assert_failed(self._verify(), "invalid governed provenance value")

    def test_malformed_workflow_run_fails(self) -> None:
        self._amend_trailers(self._trailers(workflow_run="https://example.invalid/run/1"))
        self.assert_failed(self._verify(), "invalid governed provenance value")

    def test_unknown_key_id_fails(self) -> None:
        self._amend_trailers(self._trailers(key_id=f"ed25519-spki-sha256-{'0' * 64}"))
        self.assert_failed(self._verify(), "does not match the reviewed public key")

    def test_tampered_signature_fails(self) -> None:
        trailers = self._trailers()
        trailers[-1] = f"HMG-Provenance-Signature-Ed25519: {'A' * 86}=="
        self._amend_trailers(trailers)
        self.assert_failed(self._verify(), "signature is not trusted")

    def test_untrusted_public_key_fails(self) -> None:
        other_private = self.root / "other-private.pem"
        other_public = self.root / "other-public.pem"
        run("openssl", "genpkey", "-algorithm", "ED25519", "-out", str(other_private))
        run("openssl", "pkey", "-in", str(other_private), "-pubout", "-out", str(other_public))
        self.assert_failed(self._verify(public_key=other_public), "does not match the reviewed public key")

    def test_signed_but_mismatched_source_and_export_tree_fails(self) -> None:
        mismatched_tree = f"sha1:{'0' * 40}"
        self._amend_trailers(self._trailers(source_tree=mismatched_tree))
        self.assert_failed(self._verify(), "signed source and export trees must be identical")

    def test_target_only_path_fails(self) -> None:
        (self.target / "target-only.txt").write_text("not in HMG\n", encoding="utf-8")
        self.target_sha = self._commit_target()
        self.assert_failed(self._verify(), "signed source and export trees must be identical")

    def test_target_only_content_change_fails(self) -> None:
        (self.target / "README.md").write_text("mirror-only fix\n", encoding="utf-8")
        self.target_sha = self._commit_target()
        self.assert_failed(self._verify(), "signed source and export trees must be identical")

    def test_target_only_mode_change_fails(self) -> None:
        os.chmod(self.target / "run.sh", 0o644)
        self.target_sha = self._commit_target()
        self.assert_failed(self._verify(), "signed source and export trees must be identical")

    def test_merge_group_fails_closed_until_semantics_are_defined(self) -> None:
        self.assert_failed(self._verify(event_name="merge_group"), "only pull_request events are supported")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Fail-closed verifier for signed HMG private exact-source mirrors."""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path


CONTRACT = "HMG-PRIVATE-SOURCE-MIRROR-V1"
SOURCE_REPOSITORY = "HMG-AI/HMG"
SOURCE_AUTHORITY_REF = "refs/heads/main"
TARGET_REPOSITORY = "HMG-AI/HMG-DEV-brach"
TARGET_BASE_REF = "main"
GOVERNED_TRAILER_KEYS = (
    "HMG-Mirror-Contract",
    "HMG-Source-Repository",
    "HMG-Source-SHA",
    "HMG-Source-Tree",
    "HMG-Export-Tree",
    "HMG-Workflow-Run",
    "HMG-Provenance-Key-ID",
    "HMG-Provenance-Signature-Ed25519",
)
SHA1_RE = re.compile(r"[0-9a-f]{40}")
TREE_RE = re.compile(r"sha1:[0-9a-f]{40}")
WORKFLOW_RUN_RE = re.compile(r"https://github\.com/HMG-AI/HMG/actions/runs/[1-9][0-9]*")
KEY_ID_RE = re.compile(r"ed25519-spki-sha256-[0-9a-f]{64}")
SIGNATURE_RE = re.compile(r"[A-Za-z0-9+/]{86}==")


class VerificationError(RuntimeError):
    """A deterministic private-mirror contract failure."""


def run(*args: str, input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        list(args),
        input=input_bytes,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def git(repository: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    result = run("git", "-C", str(repository), *args)
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout).decode(errors="replace").strip()
        raise VerificationError(detail or "git command failed")
    return result


def git_output(repository: Path, *args: str) -> str:
    return git(repository, *args).stdout.decode().strip()


def require_repository(path: Path, label: str) -> None:
    if not path.is_dir():
        raise VerificationError(f"{label} repository directory is absent")
    if git(path, "rev-parse", "--is-inside-work-tree", check=False).stdout.decode().strip() != "true":
        raise VerificationError(f"{label} directory is not a Git worktree")
    if git_output(path, "rev-parse", "--show-object-format") != "sha1":
        raise VerificationError(f"{label} repository must use the governed sha1 object format")


def require_single_commit_candidate(target: Path, target_base_sha: str, target_sha: str) -> None:
    if SHA1_RE.fullmatch(target_base_sha) is None:
        raise VerificationError("target base SHA must be a lowercase 40-character SHA-1")
    if git(target, "cat-file", "-e", f"{target_base_sha}^{{commit}}", check=False).returncode != 0:
        raise VerificationError("target base commit is absent")

    commit_count = git_output(target, "rev-list", "--count", f"{target_base_sha}..{target_sha}")
    if commit_count != "1":
        raise VerificationError("candidate range must contain exactly one commit")

    parents = git_output(target, "show", "-s", "--format=%P", target_sha).split()
    if parents != [target_base_sha]:
        raise VerificationError(
            "candidate commit must have exactly one parent equal to the event base SHA"
        )


def parse_trailers(target: Path, target_sha: str) -> dict[str, str]:
    message = git(target, "show", "-s", "--format=%B", target_sha).stdout
    parsed = run("git", "interpret-trailers", "--parse", input_bytes=message)
    if parsed.returncode != 0:
        raise VerificationError(
            parsed.stderr.decode(errors="replace").strip()
            or "could not parse target commit trailers"
        )

    lines = [line for line in parsed.stdout.decode().splitlines() if line]
    entries: list[tuple[str, str]] = []
    for line in lines:
        if ": " not in line:
            raise VerificationError("mirror commit contains a malformed trailer")
        key, value = line.split(": ", 1)
        entries.append((key, value))

    keys = [key for key, _ in entries]
    if len(entries) != len(GOVERNED_TRAILER_KEYS) or sorted(keys) != sorted(GOVERNED_TRAILER_KEYS):
        raise VerificationError("mirror commit must contain exactly the eight governed trailers")
    return dict(entries)


def canonical_statement(trailers: dict[str, str]) -> bytes:
    return (
        "\n".join(
            (
                CONTRACT,
                f"source-repository={SOURCE_REPOSITORY}",
                f"source-ref={SOURCE_AUTHORITY_REF}",
                f"source-sha={trailers['HMG-Source-SHA']}",
                f"source-tree={trailers['HMG-Source-Tree']}",
                f"export-tree={trailers['HMG-Export-Tree']}",
                f"workflow-run={trailers['HMG-Workflow-Run']}",
                f"target-repository={TARGET_REPOSITORY}",
                f"target-branch={TARGET_BASE_REF}",
                f"key-id={trailers['HMG-Provenance-Key-ID']}",
            )
        )
        + "\n"
    ).encode()


def trusted_key_id(public_key: Path) -> str:
    if not public_key.is_file():
        raise VerificationError("the reviewed provenance public key is absent")
    result = run("openssl", "pkey", "-pubin", "-in", str(public_key), "-outform", "DER")
    if result.returncode != 0 or not result.stdout:
        raise VerificationError("the reviewed provenance public key is invalid")
    return f"ed25519-spki-sha256-{hashlib.sha256(result.stdout).hexdigest()}"


def decode_signature(value: str) -> bytes:
    if SIGNATURE_RE.fullmatch(value) is None:
        raise VerificationError("mirror provenance signature is not canonical Ed25519 base64")
    try:
        signature = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as error:
        raise VerificationError("mirror provenance signature is not canonical Ed25519 base64") from error
    if len(signature) != 64 or base64.b64encode(signature).decode() != value:
        raise VerificationError("mirror provenance signature is not canonical Ed25519 base64")
    return signature


def verify_signature(public_key: Path, statement: bytes, signature: bytes) -> None:
    with tempfile.TemporaryDirectory(prefix="hmg-private-mirror-verify-") as temp_dir:
        statement_path = Path(temp_dir) / "statement.txt"
        signature_path = Path(temp_dir) / "signature.bin"
        statement_path.write_bytes(statement)
        signature_path.write_bytes(signature)
        result = run(
            "openssl",
            "pkeyutl",
            "-verify",
            "-pubin",
            "-inkey",
            str(public_key),
            "-rawin",
            "-in",
            str(statement_path),
            "-sigfile",
            str(signature_path),
        )
    if result.returncode != 0:
        raise VerificationError("mirror provenance signature is not trusted")


def verify(args: argparse.Namespace) -> None:
    if args.event_name != "pull_request":
        raise VerificationError("only pull_request events are supported; merge_group fails closed")
    if args.target_repository != TARGET_REPOSITORY:
        raise VerificationError(f"target repository must be {TARGET_REPOSITORY}")
    if args.target_base_ref != TARGET_BASE_REF:
        raise VerificationError(f"target base ref must be {TARGET_BASE_REF}")
    if SHA1_RE.fullmatch(args.target_sha) is None:
        raise VerificationError("target SHA must be a lowercase 40-character SHA-1")

    target = args.target_repository_dir.resolve()
    public_key = args.trusted_public_key.resolve()
    require_repository(target, "target")
    if git(target, "cat-file", "-e", f"{args.target_sha}^{{commit}}", check=False).returncode != 0:
        raise VerificationError("target commit is absent")
    require_single_commit_candidate(target, args.target_base_sha, args.target_sha)

    trailers = parse_trailers(target, args.target_sha)
    if trailers["HMG-Mirror-Contract"] != CONTRACT:
        raise VerificationError("invalid governed provenance value for HMG-Mirror-Contract")
    if trailers["HMG-Source-Repository"] != SOURCE_REPOSITORY:
        raise VerificationError("invalid governed provenance value for HMG-Source-Repository")
    if SHA1_RE.fullmatch(trailers["HMG-Source-SHA"]) is None:
        raise VerificationError("invalid governed provenance value for HMG-Source-SHA")
    if TREE_RE.fullmatch(trailers["HMG-Source-Tree"]) is None:
        raise VerificationError("invalid governed provenance value for HMG-Source-Tree")
    if TREE_RE.fullmatch(trailers["HMG-Export-Tree"]) is None:
        raise VerificationError("invalid governed provenance value for HMG-Export-Tree")
    if WORKFLOW_RUN_RE.fullmatch(trailers["HMG-Workflow-Run"]) is None:
        raise VerificationError("invalid governed provenance value for HMG-Workflow-Run")
    if KEY_ID_RE.fullmatch(trailers["HMG-Provenance-Key-ID"]) is None:
        raise VerificationError("invalid governed provenance value for HMG-Provenance-Key-ID")

    expected_key_id = trusted_key_id(public_key)
    if trailers["HMG-Provenance-Key-ID"] != expected_key_id:
        raise VerificationError("mirror provenance key ID does not match the reviewed public key")
    signature = decode_signature(trailers["HMG-Provenance-Signature-Ed25519"])
    verify_signature(public_key, canonical_statement(trailers), signature)

    actual_export_tree = f"sha1:{git_output(target, 'rev-parse', f'{args.target_sha}^{{tree}}')}"
    if actual_export_tree != trailers["HMG-Export-Tree"]:
        raise VerificationError("actual target tree does not match HMG-Export-Tree")
    if trailers["HMG-Source-Tree"] != trailers["HMG-Export-Tree"]:
        raise VerificationError("signed source and export trees must be identical")

    print(
        "private source mirror verified: "
        f"source={SOURCE_REPOSITORY}@{trailers['HMG-Source-SHA']} "
        f"target={TARGET_REPOSITORY}@{args.target_sha} "
        f"tree={actual_export_tree}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-repository-dir", type=Path, required=True)
    parser.add_argument("--target-sha", required=True)
    parser.add_argument("--target-base-sha", required=True)
    parser.add_argument("--event-name", required=True)
    parser.add_argument("--target-repository", required=True)
    parser.add_argument("--target-base-ref", required=True)
    parser.add_argument("--trusted-public-key", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    try:
        verify(parse_args())
    except VerificationError as error:
        print(f"private source mirror verification failed: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

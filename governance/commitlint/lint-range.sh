#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly SHA_PATTERN='^[0-9a-f]{40}$'

usage() {
  echo "usage: $0 <repository-path> <base-sha> <head-sha>" >&2
}

fail_input() {
  echo "commitlint input error: $*" >&2
  exit 2
}

if [[ $# -ne 3 ]]; then
  usage
  exit 2
fi

readonly REPOSITORY_PATH="$1"
readonly BASE_SHA="$2"
readonly HEAD_SHA="$3"
readonly COMMITLINT_BIN="${SCRIPT_DIR}/node_modules/.bin/commitlint"
readonly TRUSTED_CONFIG="${SCRIPT_DIR}/commitlint.config.mjs"

if ! git -C "${REPOSITORY_PATH}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail_input "repository path is not a Git worktree: ${REPOSITORY_PATH}"
fi

for sha_name in BASE_SHA HEAD_SHA; do
  sha_value="${!sha_name}"
  if [[ ! "${sha_value}" =~ ${SHA_PATTERN} ]]; then
    fail_input "${sha_name} must be a full 40-character lowercase hexadecimal commit SHA"
  fi

  if ! git -C "${REPOSITORY_PATH}" cat-file -e "${sha_value}^{commit}" 2>/dev/null; then
    fail_input "${sha_name} does not identify a commit in the checked-out repository"
  fi
done

if [[ ! -x "${COMMITLINT_BIN}" ]]; then
  echo "commitlint runtime is missing; run npm ci in ${SCRIPT_DIR}" >&2
  exit 2
fi

mapfile -t commits < <(
  git -C "${REPOSITORY_PATH}" rev-list --reverse "${BASE_SHA}..${HEAD_SHA}"
)

if [[ ${#commits[@]} -eq 0 ]]; then
  fail_input "${BASE_SHA}..${HEAD_SHA} contains no commits"
fi

lint_status=0
for commit_sha in "${commits[@]}"; do
  echo "Linting commit ${commit_sha}"
  if ! git -C "${REPOSITORY_PATH}" show --no-patch --format=%B "${commit_sha}" \
    | "${COMMITLINT_BIN}" \
      --config "${TRUSTED_CONFIG}" \
      --cwd "${SCRIPT_DIR}" \
      --verbose; then
    lint_status=1
  fi
done

exit "${lint_status}"

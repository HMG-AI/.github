#!/usr/bin/env bash
set -euo pipefail

readonly POLICY_RELATIVE_PATH="governance/workflow-policy/check.rb"
readonly FULL_SHA_PATTERN='^[0-9a-f]{40}$'

: "${POLICY_SOURCE_DIR:?POLICY_SOURCE_DIR is required}"
: "${TARGET_REPOSITORY_DIR:?TARGET_REPOSITORY_DIR is required}"
: "${WORKFLOW_SHA:?WORKFLOW_SHA is required}"
: "${BASE_SHA:?BASE_SHA is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"

for sha in "$WORKFLOW_SHA" "$BASE_SHA" "$HEAD_SHA"; do
  if [[ ! "$sha" =~ $FULL_SHA_PATTERN ]]; then
    echo "workflow-policy: SHA must be an exact lowercase 40-character value" >&2
    exit 2
  fi
done

for directory in "$POLICY_SOURCE_DIR" "$TARGET_REPOSITORY_DIR"; do
  if [[ ! -d "$directory" || -L "$directory" ]]; then
    echo "workflow-policy: checkout must be a real directory: $directory" >&2
    exit 2
  fi
done

source_root="$(git -C "$POLICY_SOURCE_DIR" rev-parse --show-toplevel)"
target_root="$(git -C "$TARGET_REPOSITORY_DIR" rev-parse --show-toplevel)"
if [[ "$(cd "$POLICY_SOURCE_DIR" && pwd -P)" != "$(cd "$source_root" && pwd -P)" ]]; then
  echo "workflow-policy: policy checkout is not its Git root" >&2
  exit 2
fi
if [[ "$(cd "$TARGET_REPOSITORY_DIR" && pwd -P)" != "$(cd "$target_root" && pwd -P)" ]]; then
  echo "workflow-policy: target checkout is not its Git root" >&2
  exit 2
fi

if [[ "$(git -C "$source_root" rev-parse HEAD)" != "$WORKFLOW_SHA" ]]; then
  echo "workflow-policy: policy checkout does not match github.workflow_sha" >&2
  exit 2
fi
if [[ "$(git -C "$target_root" rev-parse HEAD)" != "$HEAD_SHA" ]]; then
  echo "workflow-policy: target checkout does not match the event head SHA" >&2
  exit 2
fi
git -C "$target_root" cat-file -e "${BASE_SHA}^{commit}"

checker="$source_root/$POLICY_RELATIVE_PATH"
if [[ ! -f "$checker" || -L "$checker" ]]; then
  echo "workflow-policy: immutable policy checker is missing or not a regular file" >&2
  exit 2
fi

read -r mode type object _ < <(git -C "$source_root" ls-tree "$WORKFLOW_SHA" -- "$POLICY_RELATIVE_PATH")
if [[ "$mode" != "100644" && "$mode" != "100755" ]] || [[ "$type" != "blob" ]]; then
  echo "workflow-policy: checker is not a regular blob at github.workflow_sha" >&2
  exit 2
fi
if [[ "$(git -C "$source_root" hash-object "$checker")" != "$object" ]]; then
  echo "workflow-policy: checked-out policy differs from github.workflow_sha" >&2
  exit 2
fi

exec ruby "$checker" \
  --repository "$target_root" \
  --scope changed \
  --base "$BASE_SHA" \
  --head "$HEAD_SHA"

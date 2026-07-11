#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly HERE
readonly CHECKER="$HERE/check.rb"
readonly RUNNER="$HERE/run.sh"
readonly FIXTURES="$HERE/fixtures"

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
test_number=0

fail() {
  echo "not ok $test_number - $*" >&2
  exit 1
}

pass() {
  echo "ok $test_number - $*"
}

new_repository() {
  local repository="$1"
  mkdir -p "$repository/.github/workflows"
  git -C "$repository" init -q -b main
  git -C "$repository" config user.name workflow-policy-test
  git -C "$repository" config user.email workflow-policy-test@example.invalid
  cp "$FIXTURES/good-pull-request.yml" "$repository/.github/workflows/baseline.yml"
  git -C "$repository" add .
  git -C "$repository" commit -qm baseline
}

run_checker() {
  local repository="$1"
  local base="$2"
  local head="$3"
  set +e
  checker_output="$(ruby "$CHECKER" --repository "$repository" --scope changed --base "$base" --head "$head" 2>&1)"
  checker_status=$?
  set -e
}

commit_fixture() {
  local repository="$1"
  local fixture="$2"
  cp "$FIXTURES/$fixture" "$repository/.github/workflows/candidate.yml"
  git -C "$repository" add .
  git -C "$repository" commit -qm "$fixture"
}

expect_fixture() {
  local fixture="$1"
  local expected_status="$2"
  local expected_text="$3"
  local repository="$tmp_root/fixture-${test_number}"
  local base head
  test_number=$((test_number + 1))
  new_repository "$repository"
  base="$(git -C "$repository" rev-parse HEAD)"
  commit_fixture "$repository" "$fixture"
  head="$(git -C "$repository" rev-parse HEAD)"
  run_checker "$repository" "$base" "$head"
  [[ "$checker_status" -eq "$expected_status" ]] || fail "$fixture returned $checker_status: $checker_output"
  [[ "$checker_output" == *"$expected_text"* ]] || fail "$fixture omitted $expected_text: $checker_output"
  pass "$fixture"
}

expect_fixture good-pull-request.yml 0 "checked=1 violations=0"
expect_fixture good-release.yml 0 "checked=1 violations=0"
expect_fixture bad-unpinned-action.yml 1 "uses.unpinned"
expect_fixture bad-unpinned-docker.yml 1 "uses.docker_unpinned"
expect_fixture bad-missing-permissions.yml 1 "permissions.missing"
expect_fixture bad-write-all.yml 1 "permissions.write_all"
expect_fixture bad-pull-request-target.yml 1 "trigger.pull_request_target"
expect_fixture bad-pr-write.yml 1 "permissions.pr_write"
expect_fixture bad-pr-self-hosted.yml 1 "runner.pr_self_hosted"
expect_fixture bad-pr-dynamic-runner.yml 1 "runner.pr_untrusted_expression"
expect_fixture bad-pr-matrix-runner.yml 1 "runner.pr_untrusted_expression"
expect_fixture bad-pr-runner-group.yml 1 "runner.pr_unapproved"
expect_fixture bad-container.yml 1 "container.unpinned"
expect_fixture bad-checkout-persist.yml 1 "checkout.persist_credentials"
expect_fixture bad-checkout-token.yml 1 "checkout.pr_credential"
expect_fixture bad-run-injection.yml 1 "script.untrusted_expression"
expect_fixture bad-run-bracket-injection.yml 1 "script.untrusted_expression"
expect_fixture bad-github-script-injection.yml 1 "script.untrusted_expression"
expect_fixture bad-direct-main-push.yml 1 "script.direct_main_push"
expect_fixture bad-direct-main-api.yml 1 "script.direct_main_api"
expect_fixture bad-github-script-main-api.yml 1 "script.direct_main_api"
expect_fixture bad-malformed.yml 1 "yaml.parse"
expect_fixture bad-multi-document.yml 1 "yaml.document_count"
expect_fixture bad-alias.yml 1 "yaml.alias"
expect_fixture bad-duplicate-key.yml 1 "yaml.duplicate_key"
expect_fixture bad-root.yml 1 "yaml.root"

test_number=$((test_number + 1))
repo="$tmp_root/no-change"
new_repository "$repo"
sha="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$sha" "$sha"
[[ "$checker_status" -eq 0 && "$checker_output" == *"checked=0 violations=0"* ]] || fail "no-change diff was not empty: $checker_output"
pass "no changed workflows"

test_number=$((test_number + 1))
repo="$tmp_root/deletion"
new_repository "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" rm -q .github/workflows/baseline.yml
git -C "$repo" commit -qm deletion
head="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 0 && "$checker_output" == *"checked=0 violations=0"* ]] || fail "deleted workflow was inspected: $checker_output"
pass "deleted workflows are not inspected"

test_number=$((test_number + 1))
repo="$tmp_root/modification"
new_repository "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
cp "$FIXTURES/bad-unpinned-action.yml" "$repo/.github/workflows/baseline.yml"
git -C "$repo" add .
git -C "$repo" commit -qm modification
head="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 1 && "$checker_output" == *"uses.unpinned"* ]] || fail "modified unsafe workflow passed: $checker_output"
pass "modified workflow is inspected"

test_number=$((test_number + 1))
repo="$tmp_root/copy"
new_repository "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
cp "$repo/.github/workflows/baseline.yml" "$repo/.github/workflows/copied.yml"
printf '# source changed\n' >> "$repo/.github/workflows/baseline.yml"
git -C "$repo" add .
git -C "$repo" commit -qm copy
head="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 0 && "$checker_output" == *"checked=2 violations=0"* ]] || fail "copied workflow destination was not inspected: $checker_output"
pass "copied workflow destination is inspected"

test_number=$((test_number + 1))
repo="$tmp_root/rename"
new_repository "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" mv .github/workflows/baseline.yml .github/workflows/renamed.yaml
git -C "$repo" commit -qm rename
head="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 0 && "$checker_output" == *"checked=1 violations=0"* ]] || fail "renamed workflow was not inspected: $checker_output"
pass "renamed workflow destination is inspected"

test_number=$((test_number + 1))
repo="$tmp_root/rename-negative"
new_repository "$repo"
cp "$FIXTURES/bad-unpinned-action.yml" "$repo/.github/workflows/legacy.yml"
git -C "$repo" add .
git -C "$repo" commit -qm legacy
base="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" mv .github/workflows/legacy.yml .github/workflows/renamed.yml
git -C "$repo" commit -qm rename
head="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 1 && "$checker_output" == *"uses.unpinned"* ]] || fail "unsafe renamed workflow passed: $checker_output"
pass "unsafe renamed workflow fails"

test_number=$((test_number + 1))
repo="$tmp_root/oversized"
new_repository "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
cp "$FIXTURES/good-release.yml" "$repo/.github/workflows/oversized.yml"
ruby -e 'File.open(ARGV.fetch(0), "a") { |file| file.write("# padding\n" * 30_000) }' "$repo/.github/workflows/oversized.yml"
git -C "$repo" add .
git -C "$repo" commit -qm oversized
head="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 1 && "$checker_output" == *"file.oversized"* ]] || fail "oversized workflow passed: $checker_output"
pass "oversized workflow fails closed"

test_number=$((test_number + 1))
repo="$tmp_root/symlink"
new_repository "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
ln -s baseline.yml "$repo/.github/workflows/link.yml"
git -C "$repo" add .
git -C "$repo" commit -qm symlink
head="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 1 && "$checker_output" == *"file.non_regular"* ]] || fail "symlink workflow passed: $checker_output"
pass "symlink workflow fails closed"

test_number=$((test_number + 1))
repo="$tmp_root/symlink-type-change"
new_repository "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
rm "$repo/.github/workflows/baseline.yml"
ln -s ../outside.yml "$repo/.github/workflows/baseline.yml"
git -C "$repo" add .
git -C "$repo" commit -qm symlink-type-change
head="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 1 && "$checker_output" == *"file.non_regular"* ]] || fail "workflow symlink type change passed: $checker_output"
pass "workflow symlink type change fails closed"

test_number=$((test_number + 1))
repo="$tmp_root/control-path"
new_repository "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
control_path="$repo/.github/workflows/"$'control\n.yml'
cp "$FIXTURES/good-release.yml" "$control_path"
git -C "$repo" add .
git -C "$repo" commit -qm control-path
head="$(git -C "$repo" rev-parse HEAD)"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 1 && "$checker_output" == *"path.invalid"* && "$checker_output" == *"%0A"* ]] || fail "control-character workflow path did not fail safely: $checker_output"
pass "control-character workflow path fails with escaped annotation"

test_number=$((test_number + 1))
repo="$tmp_root/head-mismatch"
new_repository "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
commit_fixture "$repo" good-release.yml
head="$(git -C "$repo" rev-parse HEAD)"
printf '# uncommitted mutation\n' >> "$repo/.github/workflows/candidate.yml"
run_checker "$repo" "$base" "$head"
[[ "$checker_status" -eq 1 && "$checker_output" == *"file.head_mismatch"* ]] || fail "working-tree mutation passed as exact event head: $checker_output"
pass "workflow bytes must match the exact event head"

test_number=$((test_number + 1))
source_repo="$tmp_root/policy-source"
target_repo="$tmp_root/policy-target"
mkdir -p "$source_repo/governance/workflow-policy"
git -C "$source_repo" init -q -b main
git -C "$source_repo" config user.name workflow-policy-test
git -C "$source_repo" config user.email workflow-policy-test@example.invalid
cp "$CHECKER" "$RUNNER" "$source_repo/governance/workflow-policy/"
git -C "$source_repo" add .
git -C "$source_repo" commit -qm policy
new_repository "$target_repo"
target_base="$(git -C "$target_repo" rev-parse HEAD)"
commit_fixture "$target_repo" good-release.yml
target_head="$(git -C "$target_repo" rev-parse HEAD)"
policy_sha="$(git -C "$source_repo" rev-parse HEAD)"
set +e
runner_output="$(
  POLICY_SOURCE_DIR="$source_repo" \
  TARGET_REPOSITORY_DIR="$target_repo" \
  WORKFLOW_SHA="$policy_sha" \
  BASE_SHA="$target_base" \
  HEAD_SHA="$target_head" \
  bash "$source_repo/governance/workflow-policy/run.sh" 2>&1
)"
runner_status=$?
set -e
[[ "$runner_status" -eq 0 && "$runner_output" == *"checked=1 violations=0"* ]] || fail "immutable runner rejected valid checkouts: $runner_output"
pass "immutable runner accepts exact policy and target SHAs"

test_number=$((test_number + 1))
set +e
runner_output="$(
  POLICY_SOURCE_DIR="$source_repo" \
  TARGET_REPOSITORY_DIR="$target_repo" \
  WORKFLOW_SHA="0000000000000000000000000000000000000000" \
  BASE_SHA="$target_base" \
  HEAD_SHA="$target_head" \
  bash "$source_repo/governance/workflow-policy/run.sh" 2>&1
)"
runner_status=$?
set -e
[[ "$runner_status" -ne 0 && "$runner_output" == *"does not match github.workflow_sha"* ]] || fail "wrong policy SHA did not fail closed: $runner_output"
pass "wrong policy SHA fails closed"

test_number=$((test_number + 1))
set +e
runner_output="$(
  POLICY_SOURCE_DIR="$source_repo" \
  TARGET_REPOSITORY_DIR="$target_repo" \
  WORKFLOW_SHA="$policy_sha" \
  BASE_SHA="$target_base" \
  HEAD_SHA="$target_base" \
  bash "$source_repo/governance/workflow-policy/run.sh" 2>&1
)"
runner_status=$?
set -e
[[ "$runner_status" -ne 0 && "$runner_output" == *"does not match the event head SHA"* ]] || fail "wrong target SHA did not fail closed: $runner_output"
pass "wrong target SHA fails closed"

test_number=$((test_number + 1))
rm "$source_repo/governance/workflow-policy/check.rb"
set +e
runner_output="$(
  POLICY_SOURCE_DIR="$source_repo" \
  TARGET_REPOSITORY_DIR="$target_repo" \
  WORKFLOW_SHA="$policy_sha" \
  BASE_SHA="$target_base" \
  HEAD_SHA="$target_head" \
  bash "$source_repo/governance/workflow-policy/run.sh" 2>&1
)"
runner_status=$?
set -e
[[ "$runner_status" -ne 0 && "$runner_output" == *"checker is missing"* ]] || fail "missing checker did not fail closed: $runner_output"
pass "missing immutable checker fails closed"

echo "1..$test_number"

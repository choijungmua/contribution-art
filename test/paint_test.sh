#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local output="$1"
  local expected="$2"
  [[ "$output" == *"$expected"* ]] || fail "expected output to contain: $expected\nactual output:\n$output"
}

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
cp paint.sh "$repo/paint.sh"
chmod +x "$repo/paint.sh"
git -C "$repo" init --quiet
git -C "$repo" config user.name Test
git -C "$repo" config user.email test@example.com

for index in $(seq 1 50); do
  git -C "$repo" commit --allow-empty --quiet -m "art: 2025-07-14 $index/50"
done

fixture="$repo/calendar.tsv"
printf '%s\n' \
  $'2025-07-14\t20\t20' \
  $'2025-07-15\t32\t20' \
  $'2025-07-20\t5\t0' \
  $'2025-07-21\t0\t0' >"$fixture"
git -C "$repo" add paint.sh calendar.tsv
git -C "$repo" commit --quiet -m fixture

output="$(
  cd "$repo"
  ART_TODAY=2025-07-21 \
  ART_CALENDAR_FILE="$fixture" \
  ART_PENDING_HOURS=0 \
    ./paint.sh plan
)"

assert_contains "$output" $'2025-07-14\tletter\ttotal=20\tart=20\tuser=0\tpending=0\tadd=30'
assert_contains "$output" $'2025-07-15\tletter\ttotal=32\tart=20\tuser=12\tpending=0\tadd=18'
assert_contains "$output" $'2025-07-21\tbackground\ttotal=0\tart=0\tuser=0\tpending=0\tadd=1'
assert_contains "$output" $'target=50\tplanned=49'

limited_output="$(
  cd "$repo"
  ART_TODAY=2025-07-21 \
  ART_CALENDAR_FILE="$fixture" \
  ART_PENDING_HOURS=0 \
  ART_BATCH_LIMIT=25 \
    ./paint.sh plan
)"

assert_contains "$limited_output" $'2025-07-14\tletter\ttotal=20\tart=20\tuser=0\tpending=0\tadd=25'
assert_contains "$limited_output" $'target=50\tplanned=25\tdeferred=24'

sync_output="$(
  cd "$repo"
  ART_TODAY=2025-07-21 \
  ART_CALENDAR_FILE="$fixture" \
  ART_PENDING_HOURS=0 \
  ART_BATCH_LIMIT=25 \
    ./paint.sh sync
)"

sync_count="$(git -C "$repo" log --format='%s' --grep='^art-sync:' | wc -l | tr -d '[:space:]')"
[[ "$sync_count" == "25" ]] || fail "expected sync to create 25 commits, got $sync_count"
[[ "$(git -C "$repo" show -s --format='%as' HEAD)" == "2025-07-14" ]] || fail "expected target author date on adaptive commit"
assert_contains "$sync_output" "2025-07-14: added 25 adaptive commit(s)"

printf 'PASS: adaptive plan uses displayed totals and user contributions\n'

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

GIT_AUTHOR_NAME=CJM \
GIT_AUTHOR_EMAIL=158401607+choijungmua@users.noreply.github.com \
GIT_AUTHOR_DATE=2025-07-15T12:00:00Z \
  git -C "$repo" commit --allow-empty --quiet -m "real work in art repository"
GIT_AUTHOR_NAME=CJM \
GIT_AUTHOR_EMAIL=158401607+choijungmua@users.noreply.github.com \
GIT_AUTHOR_DATE=2025-07-20T12:00:00Z \
  git -C "$repo" commit --allow-empty --quiet -m "more real work in art repository"

fixture="$repo/calendar.tsv"
printf '%s\n' \
  $'2025-07-14\t20\t20' \
  $'2025-07-15\t32\t21' \
  $'2025-07-20\t52\t1' \
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

assert_contains "$output" $'2025-07-14\tletter\ttotal=20\trepo=20\tlocal=0\tuser=0\tpending=0\tadd=33'
assert_contains "$output" $'2025-07-15\tletter\ttotal=32\trepo=21\tlocal=1\tuser=12\tpending=0\tadd=21'
assert_contains "$output" $'2025-07-21\tbackground\ttotal=0\trepo=0\tlocal=0\tuser=0\tpending=0\tadd=1'
assert_contains "$output" $'target=53\tplanned=55'

limited_output="$(
  cd "$repo"
  ART_TODAY=2025-07-21 \
  ART_CALENDAR_FILE="$fixture" \
  ART_PENDING_HOURS=0 \
  ART_BATCH_LIMIT=25 \
    ./paint.sh plan
)"

assert_contains "$limited_output" $'2025-07-14\tletter\ttotal=20\trepo=20\tlocal=0\tuser=0\tpending=0\tadd=25'
assert_contains "$limited_output" $'target=53\tplanned=25\tdeferred=30'

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

printf '%s\n' \
  $'2025-07-14\t45\t45' \
  $'2025-07-15\t32\t21' \
  $'2025-07-20\t52\t1' \
  $'2025-07-21\t0\t0' >"$fixture"
reflected_output="$(
  cd "$repo"
  ART_TODAY=2025-07-21 \
  ART_CALENDAR_FILE="$fixture" \
  ART_PENDING_HOURS=72 \
    ./paint.sh plan
)"

assert_contains "$reflected_output" $'2025-07-14\tletter\ttotal=45\trepo=45\tlocal=0\tuser=0\tpending=0\tadd=8'

printf 'PASS: adaptive plan uses displayed totals and user contributions\n'

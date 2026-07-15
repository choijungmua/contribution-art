#!/usr/bin/env bash
set -euo pipefail

readonly AUTHOR_NAME="${ART_AUTHOR_NAME:-CJM}"
readonly AUTHOR_EMAIL="${ART_AUTHOR_EMAIL:-158401607+choijungmua@users.noreply.github.com}"
readonly GITHUB_LOGIN="${ART_GITHUB_LOGIN:-choijungmua}"
readonly ART_REPOSITORY="${ART_REPOSITORY:-choijungmua/contribution-art}"
readonly EPOCH_SUNDAY="${ART_EPOCH_SUNDAY:-2025-07-13}"
readonly LIGHT_COMMITS="${ART_LIGHT_COMMITS:-1}"
readonly DARK_COMMITS="${ART_DARK_COMMITS:-50}"
readonly DARK_MARGIN="${ART_DARK_MARGIN:-1}"
readonly BATCH_LIMIT="${ART_BATCH_LIMIT:-250}"
readonly PENDING_HOURS="${ART_PENDING_HOURS:-72}"
readonly GH_BIN="${ART_GH_BIN:-gh}"
readonly PATTERN_WIDTH=20

readonly -a PATTERN_ROWS=(
  "10101110100010001110"
  "10101000100010001010"
  "11101100100010001010"
  "10101000100010001010"
  "10101110111011101110"
)

declare -A CALENDAR_TOTALS=()
declare -A CALENDAR_REPO_TOTALS=()
declare -A LOCAL_USER_TOTALS=()
declare -A PENDING_TOTALS=()
declare -a CALENDAR_DATES=()

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

validate_config() {
  [[ "$LIGHT_COMMITS" =~ ^[1-9][0-9]*$ ]] || die "ART_LIGHT_COMMITS must be a positive integer"
  [[ "$DARK_COMMITS" =~ ^[1-9][0-9]*$ ]] || die "ART_DARK_COMMITS must be a positive integer"
  [[ "$DARK_MARGIN" =~ ^[0-9]+$ ]] || die "ART_DARK_MARGIN must be a non-negative integer"
  [[ "$BATCH_LIMIT" =~ ^[1-9][0-9]*$ ]] || die "ART_BATCH_LIMIT must be a positive integer"
  [[ "$PENDING_HOURS" =~ ^[0-9]+$ ]] || die "ART_PENDING_HOURS must be a non-negative integer"
  (( DARK_COMMITS > LIGHT_COMMITS )) || die "dark commit count must exceed light commit count"
  [[ "$ART_REPOSITORY" == */* ]] || die "ART_REPOSITORY must use owner/name"

  local row
  for row in "${PATTERN_ROWS[@]}"; do
    (( ${#row} == PATTERN_WIDTH )) || die "invalid pattern row width"
  done

  date -u -d "$EPOCH_SUNDAY" +%F >/dev/null 2>&1 || die "invalid ART_EPOCH_SUNDAY"
  [[ "$(date -u -d "$EPOCH_SUNDAY" +%w)" == "0" ]] || die "ART_EPOCH_SUNDAY must be a Sunday"
}

week_column() {
  local target_date="$1"
  local target_epoch epoch_epoch weeks column
  target_epoch="$(date -u -d "$target_date 12:00:00" +%s)"
  epoch_epoch="$(date -u -d "$EPOCH_SUNDAY 12:00:00" +%s)"
  weeks=$(( (target_epoch - epoch_epoch) / 604800 ))
  column=$(( weeks % PATTERN_WIDTH ))
  (( column < 0 )) && column=$(( column + PATTERN_WIDTH ))
  printf '%d\n' "$column"
}

is_letter_cell() {
  local target_date="$1"
  local weekday row column
  weekday="$(date -u -d "$target_date" +%w)"
  (( weekday >= 1 && weekday <= 5 )) || return 1
  row=$(( weekday - 1 ))
  column="$(week_column "$target_date")"
  [[ "${PATTERN_ROWS[$row]:$column:1}" == "1" ]]
}

visible_window_start() {
  local today="$1"
  local weekday current_sunday
  weekday="$(date -u -d "$today" +%w)"
  current_sunday="$(date -u -d "$today -$weekday days" +%F)"
  date -u -d "$current_sunday -364 days" +%F
}

preview() {
  local today start week weekday target_date
  today="${ART_TODAY:-$(date -u +%F)}"
  start="$(visible_window_start "$today")"
  printf 'UTC window: %s through %s\n' "$start" "$today"
  printf 'Legend: # letter, . daily background, space future\n\n'

  for (( weekday = 0; weekday < 7; weekday++ )); do
    for (( week = 0; week < 53; week++ )); do
      target_date="$(date -u -d "$start +$(( week * 7 + weekday )) days" +%F)"
      if [[ "$target_date" > "$today" ]]; then
        printf ' '
      elif is_letter_cell "$target_date"; then
        printf '#'
      else
        printf '.'
      fi
    done
    printf '\n'
  done
}

resolve_gh() {
  if command -v "$GH_BIN" >/dev/null 2>&1; then
    command -v "$GH_BIN"
  elif [[ -x "/c/Program Files/GitHub CLI/gh.exe" ]]; then
    printf '%s\n' "/c/Program Files/GitHub CLI/gh.exe"
  else
    die "GitHub CLI not found; set ART_GH_BIN"
  fi
}

fetch_live_calendar() {
  local output="$1"
  local start="$2"
  local today="$3"
  local temp_dir="$4"
  local gh from to calendar_query art_query actual_repo
  local totals_file="$temp_dir/totals.tsv"
  local art_file="$temp_dir/art.tsv"
  gh="$(resolve_gh)"
  from="${start}T00:00:00Z"
  to="${today}T23:59:59Z"
  calendar_query='query($login:String!,$from:DateTime!,$to:DateTime!){user(login:$login){contributionsCollection(from:$from,to:$to){contributionCalendar{weeks{contributionDays{date contributionCount}}}}}}'
  art_query='query($login:String!,$from:DateTime!,$to:DateTime!,$endCursor:String){user(login:$login){contributionsCollection(from:$from,to:$to){commitContributionsByRepository(maxRepositories:1){repository{nameWithOwner} contributions(first:100,after:$endCursor){nodes{occurredAt commitCount} pageInfo{hasNextPage endCursor}}}}}}'

  "$gh" api graphql -f query="$calendar_query" -F login="$GITHUB_LOGIN" -F from="$from" -F to="$to" \
    --jq '.data.user.contributionsCollection.contributionCalendar.weeks[].contributionDays[] | [.date, .contributionCount] | @tsv' >"$totals_file"
  "$gh" api graphql --paginate -f query="$art_query" -F login="$GITHUB_LOGIN" -F from="$from" -F to="$to" \
    --jq '.data.user.contributionsCollection.commitContributionsByRepository[] | .repository.nameWithOwner as $repo | .contributions.nodes[] | [$repo, .occurredAt[0:10], .commitCount] | @tsv' >"$art_file"

  actual_repo="$(cut -f1 "$art_file" | sort -u)"
  [[ "$actual_repo" == "$ART_REPOSITORY" ]] || die "expected top contribution repository $ART_REPOSITORY, got ${actual_repo:-none}"

  awk -F '\t' -v OFS='\t' -v expected="$ART_REPOSITORY" '
    NR == FNR { if ($1 == expected) art[$2] += $3; next }
    { print $1, $2, art[$1] + 0 }
  ' "$art_file" "$totals_file" >"$output"
}

load_calendar() {
  local calendar_file="$1"
  local target_date total repo_total extra
  while IFS=$'\t' read -r target_date total repo_total extra; do
    [[ -n "$target_date" ]] || continue
    [[ "$target_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "invalid calendar date: $target_date"
    [[ "$total" =~ ^[0-9]+$ ]] || die "invalid calendar total for $target_date"
    [[ "$repo_total" =~ ^[0-9]+$ ]] || die "invalid repository total for $target_date"
    [[ -z "${extra:-}" ]] || die "invalid calendar row for $target_date"
    CALENDAR_DATES+=("$target_date")
    CALENDAR_TOTALS["$target_date"]="$total"
    CALENDAR_REPO_TOTALS["$target_date"]="$repo_total"
  done < <(sort -t $'\t' -k1,1 -u "$calendar_file")
  (( ${#CALENDAR_DATES[@]} > 0 )) || die "calendar is empty"
}

load_pending() {
  if (( PENDING_HOURS == 0 )); then
    return 0
  fi
  local subject remainder target_date
  while IFS= read -r subject; do
    remainder="${subject#art-sync: }"
    target_date="${remainder%% *}"
    PENDING_TOTALS["$target_date"]=$(( ${PENDING_TOTALS["$target_date"]:-0} + 1 ))
  done < <(git log --since="$PENDING_HOURS hours ago" --format='%s' --extended-regexp --grep='^art-sync: [0-9]{4}-[0-9]{2}-[0-9]{2} ')
}

load_local_user_commits() {
  local author_date author_email subject target_date
  while IFS=$'\t' read -r author_date author_email subject; do
    [[ "$author_email" == "$AUTHOR_EMAIL" ]] || continue
    [[ "$subject" != art:* && "$subject" != art-sync:* ]] || continue
    target_date="${author_date:0:10}"
    LOCAL_USER_TOTALS["$target_date"]=$(( ${LOCAL_USER_TOTALS["$target_date"]:-0} + 1 ))
  done < <(git log --format='%aI%x09%ae%x09%s')
}

build_plan() {
  local plan_file="$1"
  local start="$2"
  local today="$3"
  local target="$DARK_COMMITS"
  local target_date total repo_total local_user user pending effective kind desired needed add capacity
  local planned=0 deferred=0

  for target_date in "${CALENDAR_DATES[@]}"; do
    [[ "$target_date" < "$start" || "$target_date" > "$today" ]] && continue
    total="${CALENDAR_TOTALS["$target_date"]}"
    repo_total="${CALENDAR_REPO_TOTALS["$target_date"]}"
    local_user="${LOCAL_USER_TOTALS["$target_date"]:-0}"
    user=$(( total - repo_total + local_user ))
    (( user < 0 )) && user=0
    (( user + DARK_MARGIN > target )) && target=$(( user + DARK_MARGIN ))
  done

  : >"$plan_file"
  for target_date in "${CALENDAR_DATES[@]}"; do
    [[ "$target_date" < "$start" || "$target_date" > "$today" ]] && continue
    total="${CALENDAR_TOTALS["$target_date"]}"
    repo_total="${CALENDAR_REPO_TOTALS["$target_date"]}"
    local_user="${LOCAL_USER_TOTALS["$target_date"]:-0}"
    user=$(( total - repo_total + local_user ))
    (( user < 0 )) && user=0
    pending="${PENDING_TOTALS["$target_date"]:-0}"
    effective=$(( total + pending ))
    if is_letter_cell "$target_date"; then
      kind="letter"
      desired="$target"
    else
      kind="background"
      desired="$LIGHT_COMMITS"
    fi
    needed=$(( desired - effective ))
    (( needed > 0 )) || continue
    capacity=$(( BATCH_LIMIT - planned ))
    add=0
    (( capacity > 0 )) && add="$needed"
    (( add > capacity )) && add="$capacity"
    deferred=$(( deferred + needed - add ))
    (( add > 0 )) || continue
    printf '%s\t%s\ttotal=%d\trepo=%d\tlocal=%d\tuser=%d\tpending=%d\tadd=%d\n' \
      "$target_date" "$kind" "$total" "$repo_total" "$local_user" "$user" "$pending" "$add" | tee -a "$plan_file"
    planned=$(( planned + add ))
  done
  printf 'target=%d\tplanned=%d\tdeferred=%d\n' "$target" "$planned" "$deferred"
}

existing_art_commits() {
  local target_date="$1"
  git log --format='%s' --extended-regexp --grep="^(art|art-sync): $target_date " | wc -l | tr -d '[:space:]'
}

create_commits() {
  local target_date="$1"
  local add="$2"
  local existing author_stamp committer_stamp offset sequence
  existing="$(existing_art_commits "$target_date")"
  author_stamp="${target_date}T12:00:00+00:00"
  committer_stamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  for (( offset = 1; offset <= add; offset++ )); do
    sequence=$(( existing + offset ))
    GIT_AUTHOR_NAME="$AUTHOR_NAME" \
    GIT_AUTHOR_EMAIL="$AUTHOR_EMAIL" \
    GIT_AUTHOR_DATE="$author_stamp" \
    GIT_COMMITTER_NAME="$AUTHOR_NAME" \
    GIT_COMMITTER_EMAIL="$AUTHOR_EMAIL" \
    GIT_COMMITTER_DATE="$committer_stamp" \
      git commit --allow-empty --quiet -m "art-sync: $target_date $sequence"
  done
  printf '%s: added %d adaptive commit(s)\n' "$target_date" "$add"
}

apply_plan() {
  local plan_file="$1"
  local target_date kind total repo_total local_user user pending add
  while IFS=$'\t' read -r target_date kind total repo_total local_user user pending add; do
    create_commits "$target_date" "${add#add=}"
  done <"$plan_file"
}

main() {
  validate_config
  local mode="${1:-plan}"
  local today start temp_dir calendar_file plan_file
  today="${ART_TODAY:-$(date -u +%F)}"
  date -u -d "$today" +%F >/dev/null 2>&1 || die "invalid ART_TODAY"

  if [[ "$mode" == "preview" ]]; then
    preview
    return
  fi
  [[ "$mode" == "plan" || "$mode" == "sync" ]] || die "usage: $0 [preview|plan|sync]"

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "run inside a Git repository"
  [[ "$mode" != "sync" || -z "$(git status --porcelain)" ]] || die "working tree must be clean"
  start="$(visible_window_start "$today")"
  temp_dir="$(mktemp -d)"
  trap "rm -rf '$temp_dir'" EXIT
  calendar_file="$temp_dir/calendar.tsv"
  plan_file="$temp_dir/plan.tsv"

  if [[ -n "${ART_CALENDAR_FILE:-}" ]]; then
    calendar_file="$ART_CALENDAR_FILE"
  else
    fetch_live_calendar "$calendar_file" "$start" "$today" "$temp_dir"
  fi
  load_calendar "$calendar_file"
  load_local_user_commits
  load_pending
  build_plan "$plan_file" "$start" "$today"
  [[ "$mode" == "plan" ]] || apply_plan "$plan_file"
}

main "$@"

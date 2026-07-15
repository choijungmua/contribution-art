#!/usr/bin/env bash
set -euo pipefail

readonly AUTHOR_NAME="${ART_AUTHOR_NAME:-CJM}"
readonly AUTHOR_EMAIL="${ART_AUTHOR_EMAIL:-158401607+choijungmua@users.noreply.github.com}"
readonly EPOCH_SUNDAY="${ART_EPOCH_SUNDAY:-2025-07-13}"
readonly LIGHT_COMMITS="${ART_LIGHT_COMMITS:-1}"
readonly DARK_COMMITS="${ART_DARK_COMMITS:-50}"
readonly PATTERN_WIDTH=20

readonly -a PATTERN_ROWS=(
  "10101110100010001110"
  "10101000100010001010"
  "11101100100010001010"
  "10101000100010001010"
  "10101110111011101110"
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

validate_config() {
  [[ "$LIGHT_COMMITS" =~ ^[1-9][0-9]*$ ]] || die "ART_LIGHT_COMMITS must be a positive integer"
  [[ "$DARK_COMMITS" =~ ^[1-9][0-9]*$ ]] || die "ART_DARK_COMMITS must be a positive integer"
  (( DARK_COMMITS > LIGHT_COMMITS )) || die "dark commit count must exceed light commit count"

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

desired_commits() {
  if is_letter_cell "$1"; then
    printf '%d\n' "$DARK_COMMITS"
  else
    printf '%d\n' "$LIGHT_COMMITS"
  fi
}

existing_art_commits() {
  local target_date="$1"
  git log --format='%s' --fixed-strings --grep="art: $target_date " | wc -l | tr -d '[:space:]'
}

paint_date() {
  local target_date="$1"
  local desired existing index stamp
  date -u -d "$target_date" +%F >/dev/null 2>&1 || die "invalid date: $target_date"
  desired="$(desired_commits "$target_date")"
  existing="$(existing_art_commits "$target_date")"
  (( existing >= desired )) && return 0

  stamp="${target_date}T12:00:00+00:00"
  for (( index = existing + 1; index <= desired; index++ )); do
    GIT_AUTHOR_NAME="$AUTHOR_NAME" \
    GIT_AUTHOR_EMAIL="$AUTHOR_EMAIL" \
    GIT_AUTHOR_DATE="$stamp" \
    GIT_COMMITTER_NAME="$AUTHOR_NAME" \
    GIT_COMMITTER_EMAIL="$AUTHOR_EMAIL" \
    GIT_COMMITTER_DATE="$stamp" \
      git commit --allow-empty --quiet -m "art: $target_date $index/$desired"
  done
  printf '%s: added %d commit(s)\n' "$target_date" "$(( desired - existing ))"
}

visible_window_start() {
  local today="$1"
  local weekday current_sunday
  weekday="$(date -u -d "$today" +%w)"
  current_sunday="$(date -u -d "$today -$weekday days" +%F)"
  date -u -d "$current_sunday -364 days" +%F
}

paint_range() {
  local start_date="$1"
  local end_date="$2"
  local cursor after_end
  after_end="$(date -u -d "$end_date +1 day" +%F)"
  cursor="$start_date"
  while [[ "$cursor" != "$after_end" ]]; do
    paint_date "$cursor"
    cursor="$(date -u -d "$cursor +1 day" +%F)"
  done
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

main() {
  validate_config
  local mode="${1:-today}"
  local today
  today="${ART_TODAY:-$(date -u +%F)}"

  if [[ "$mode" == "preview" ]]; then
    preview
    return
  fi

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "run inside a Git repository"
  [[ -z "$(git status --porcelain)" ]] || die "working tree must be clean"

  case "$mode" in
    today)
      paint_date "$today"
      ;;
    backfill)
      paint_range "$(visible_window_start "$today")" "$today"
      ;;
    date)
      [[ $# == 2 ]] || die "usage: $0 date YYYY-MM-DD"
      paint_date "$2"
      ;;
    *)
      die "usage: $0 [today|backfill|preview|date YYYY-MM-DD]"
      ;;
  esac
}

main "$@"

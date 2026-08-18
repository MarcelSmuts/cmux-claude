#!/usr/bin/env bats
# Unit tests for the daily-recap "last working day" resolver. These lock the
# cross-platform (BSD vs GNU `date`) window math against fixed inputs. TZ is pinned
# per run so epochs/offsets are deterministic regardless of the host's clock, and
# CMUXCLAUDE_CONFIG points at a nonexistent file so no real config leaks in.

setup() {
  DW="$BATS_TEST_DIRNAME/../claude/skills/daily-recap/scripts/day-window.sh"
}

# run_dw <TZ> [date-arg]
run_dw() {
  local tz="$1"; shift
  run env CMUXCLAUDE_CONFIG=/nonexistent CMUXCLAUDE_TZ="$tz" bash "$DW" "$@"
}

@test "Monday reaches back across the weekend to the previous Friday" {
  run_dw UTC 2024-01-01   # 2024-01-01 is a Monday
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET_DATE=2023-12-29"* ]]
  [[ "$output" == *"TARGET_WEEKDAY=Friday"* ]]
}

@test "a midweek day resolves to the previous calendar day" {
  run_dw UTC 2024-01-03   # Wednesday
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET_DATE=2024-01-02"* ]]
  [[ "$output" == *"TARGET_WEEKDAY=Tuesday"* ]]
}

@test "Saturday resolves to the previous day (Friday)" {
  run_dw UTC 2024-01-06   # Saturday
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET_DATE=2024-01-05"* ]]
  [[ "$output" == *"TARGET_WEEKDAY=Friday"* ]]
}

@test "Sunday reaches back to Friday" {
  run_dw UTC 2024-01-07   # Sunday
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET_DATE=2024-01-05"* ]]
  [[ "$output" == *"TARGET_WEEKDAY=Friday"* ]]
}

@test "full window output is exact for a fixed UTC date" {
  run_dw UTC 2024-01-03   # -> Tuesday 2024-01-02, 00:00:00..23:59:59 UTC
  [ "$status" -eq 0 ]
  [[ "$output" == *"LOCAL_OFFSET=+00:00"* ]]
  [[ "$output" == *"START_TS=1704153600"* ]]
  [[ "$output" == *"END_TS=1704239999"* ]]
  [[ "$output" == *"WINDOW_START_UTC=2024-01-02T00:00:00Z"* ]]
  [[ "$output" == *"WINDOW_END_UTC=2024-01-02T23:59:59Z"* ]]
  [[ "$output" == *"GH_RANGE=2024-01-02T00:00:00+00:00..2024-01-02T23:59:59+00:00"* ]]
}

@test "LOCAL_OFFSET is DST-aware: EDT in summer" {
  run_dw America/New_York 2024-07-10   # summer -> UTC-4
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET_DATE=2024-07-09"* ]]
  [[ "$output" == *"LOCAL_OFFSET=-04:00"* ]]
  [[ "$output" == *"GH_RANGE=2024-07-09T00:00:00-04:00..2024-07-09T23:59:59-04:00"* ]]
}

@test "LOCAL_OFFSET is DST-aware: EST in winter" {
  run_dw America/New_York 2024-01-10   # winter -> UTC-5
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET_DATE=2024-01-09"* ]]
  [[ "$output" == *"LOCAL_OFFSET=-05:00"* ]]
}

@test "an unparseable date fails with a clear message" {
  run_dw UTC not-a-date
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid date: not-a-date"* ]]
}

@test "no argument defaults to the system's today" {
  run_dw UTC
  [ "$status" -eq 0 ]
  [[ "$output" == *"TARGET_DATE="* ]]
  [[ "$output" == *"TARGET_WEEKDAY="* ]]
}

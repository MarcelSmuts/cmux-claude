#!/usr/bin/env bats
# Unit tests for lib/common.sh. It only defines functions/vars, so each test sources
# it inside an isolated `bash -c` subshell (keeps common.sh's `set -u`/pipefail from
# leaking into bats' own shell) and overrides PAYLOAD/CLAUDE_DIR to sandbox link_into.

setup() {
  COMMON="$BATS_TEST_DIRNAME/../lib/common.sh"
}

@test "have: true for an existing command" {
  run bash -c "source '$COMMON'; have bash"
  [ "$status" -eq 0 ]
}

@test "have: false for a bogus command" {
  run bash -c "source '$COMMON'; have definitely-not-a-real-command-xyz"
  [ "$status" -ne 0 ]
}

@test "log prints the message verbatim on stdout" {
  run bash -c "source '$COMMON'; log 'plain line'"
  [ "$status" -eq 0 ]
  [ "$output" = "plain line" ]
}

@test "ok/warn/err render marker + message (color stripped)" {
  # perl strip works on both GNU and BSD; \e handles the ESC of the SGR codes.
  run bash -c "source '$COMMON'; { ok 'go'; warn 'careful'; err 'nope'; } 2>&1 | perl -pe 's/\e\[[0-9;]*m//g'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ go"* ]]
  [[ "$output" == *"! careful"* ]]
  [[ "$output" == *"✗ nope"* ]]
}

@test "warn and err write to stderr, not stdout" {
  run bash -c "source '$COMMON'; { warn hush; err quiet; } 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "link_into symlinks a payload path into CLAUDE_DIR" {
  run bash -c '
    set -uo pipefail
    src_root="$(mktemp -d)"; dest_root="$(mktemp -d)"
    mkdir -p "$src_root/claude/skills/foo"
    echo hi > "$src_root/claude/skills/foo/bar.txt"
    source "'"$COMMON"'"
    PAYLOAD="$src_root/claude"; CLAUDE_DIR="$dest_root"
    link_into "skills/foo" "skills/foo" >/dev/null
    [ -L "$dest_root/skills/foo" ]
    [ "$(readlink "$dest_root/skills/foo")" = "$src_root/claude/skills/foo" ]
    [ "$(cat "$dest_root/skills/foo/bar.txt")" = hi ]
  '
  [ "$status" -eq 0 ]
}

@test "link_into backs up a pre-existing real file before linking" {
  run bash -c '
    set -uo pipefail
    src_root="$(mktemp -d)"; dest_root="$(mktemp -d)"
    mkdir -p "$src_root/claude"
    echo payload > "$src_root/claude/thing"
    echo original > "$dest_root/thing"     # a real file already sitting at the dest
    source "'"$COMMON"'"
    PAYLOAD="$src_root/claude"; CLAUDE_DIR="$dest_root"
    link_into "thing" "thing" >/dev/null 2>&1
    [ -L "$dest_root/thing" ]                                      # dest is now the symlink
    [ "$(cat "$dest_root/thing")" = payload ]                      # resolving to the payload
    [ -f "$dest_root/thing.pre-cmux-claude.bak" ]                  # the old file was preserved
    [ "$(cat "$dest_root/thing.pre-cmux-claude.bak")" = original ]
  '
  [ "$status" -eq 0 ]
}

@test "link_into replaces a stale symlink without leaving a backup" {
  run bash -c '
    set -uo pipefail
    src_root="$(mktemp -d)"; dest_root="$(mktemp -d)"
    mkdir -p "$src_root/claude"
    echo payload > "$src_root/claude/thing"
    ln -s /some/old/target "$dest_root/thing"   # a pre-existing symlink, not a real file
    source "'"$COMMON"'"
    PAYLOAD="$src_root/claude"; CLAUDE_DIR="$dest_root"
    link_into "thing" "thing" >/dev/null 2>&1
    [ "$(readlink "$dest_root/thing")" = "$src_root/claude/thing" ]
    [ ! -e "$dest_root/thing.pre-cmux-claude.bak" ]   # symlinks are replaced, not backed up
  '
  [ "$status" -eq 0 ]
}

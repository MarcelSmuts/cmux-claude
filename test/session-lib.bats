#!/usr/bin/env bats
# Unit tests for claude/scripts/session-lib.sh. Each test sources the lib in its own
# `bash -c` subshell against a stub cmux CLI (CMUX_BIN) and a sandboxed config
# (CMUX_CONFIG), so nothing here touches the real cmux or ~/.config.

setup() {
  LIB="$BATS_TEST_DIRNAME/../claude/scripts/session-lib.sh"
  CFG="$BATS_TEST_TMPDIR/cmux.json"
  STUB="$BATS_TEST_TMPDIR/cmux-stub"
  # Answers every subcommand the repair path uses; ping always succeeds.
  cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ping)          echo PONG ;;
  reload-config) echo "OK Reloaded config" ;;
  *)             exit 1 ;;
esac
EOF
  chmod +x "$STUB"
}

# Run `sc_repair_socket_password` with the lib sourced and the stub wired in.
repair() {
  run env CMUX_BIN="$STUB" CMUX_CONFIG="$CFG" CMUX_SOCKET_PASSWORD="${PW-s3cret}" \
    bash -c "source '$LIB'; sc_repair_socket_password"
}

@test "repair: re-arms the password when cmux has stripped it" {
  echo '{"automation":{"socketControlMode":"password"}}' >"$CFG"
  repair
  [ "$status" -eq 0 ]
  [ "$(jq -r '.automation.socketPassword' "$CFG")" = "s3cret" ]
  [ "$(jq -r '.automation.socketControlMode' "$CFG")" = "password" ]
}

@test "repair: keeps a backup of the config it rewrote" {
  echo '{"automation":{"socketControlMode":"password"},"theme":"dark"}' >"$CFG"
  repair
  [ "$status" -eq 0 ]
  [ -f "$CFG.pre-autorepair.bak" ]
  [ "$(jq -r '.automation.socketPassword // "none"' "$CFG.pre-autorepair.bak")" = "none" ]
  # Unrelated settings survive the rewrite.
  [ "$(jq -r '.theme' "$CFG")" = "dark" ]
}

@test "repair: leaves an existing password alone (mismatch is a manual fix)" {
  echo '{"automation":{"socketControlMode":"password","socketPassword":"theirs"}}' >"$CFG"
  repair
  [ "$status" -ne 0 ]
  [ "$(jq -r '.automation.socketPassword' "$CFG")" = "theirs" ]
}

@test "repair: no-op when the mode isn't password" {
  echo '{"automation":{"socketControlMode":"cmuxOnly"}}' >"$CFG"
  repair
  [ "$status" -ne 0 ]
  [ "$(jq -r '.automation.socketPassword // "none"' "$CFG")" = "none" ]
}

@test "repair: no-op without \$CMUX_SOCKET_PASSWORD to re-arm from" {
  echo '{"automation":{"socketControlMode":"password"}}' >"$CFG"
  PW="" repair
  [ "$status" -ne 0 ]
  [ "$(jq -r '.automation.socketPassword // "none"' "$CFG")" = "none" ]
}

@test "repair: opt out with CMUX_SOCKET_PW_AUTOREPAIR=" {
  echo '{"automation":{"socketControlMode":"password"}}' >"$CFG"
  run env CMUX_BIN="$STUB" CMUX_CONFIG="$CFG" CMUX_SOCKET_PASSWORD=s3cret \
    CMUX_SOCKET_PW_AUTOREPAIR= bash -c "source '$LIB'; sc_repair_socket_password"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.automation.socketPassword // "none"' "$CFG")" = "none" ]
}

@test "repair: missing config file is not an error to the caller" {
  rm -f "$CFG"
  repair
  [ "$status" -ne 0 ]
}

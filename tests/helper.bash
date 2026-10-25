# Shared setup: isolated HOME/XDG dirs, stubs first in PATH.
# shellcheck disable=SC2034 # FBSD and friends are used by the .bats files
setup() {
	ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
	FBSD="$ROOT/bin/fbsd"
	T=$BATS_TEST_TMPDIR
	export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data
	export XDG_RUNTIME_DIR=$T/run STUB_LOG=$T/stub.log NO_COLOR=1
	export PATH="$ROOT/tests/stubs:$PATH"
	export STUB_PIDFILE=$XDG_RUNTIME_DIR/fbsd/fbsd-dev/qemu.pid
	mkdir -p "$HOME/.ssh" "$XDG_CONFIG_HOME/fbsd" "$XDG_DATA_HOME/fbsd" "$XDG_RUNTIME_DIR"
	: >"$HOME/.ssh/id_ed25519"
	: >"$XDG_DATA_HOME/fbsd/fbsd-dev.qcow2"
	: >"$STUB_LOG"
	unset FBSD_DRYRUN FBSD_VERBOSE FBSD_CONFIG
	for k in $(env | sed -n 's/^\(FBSD_[A-Z_]*\)=.*/\1/p'); do unset "$k"; done
}

teardown() {
	if [ -f "$STUB_PIDFILE" ]; then kill "$(cat "$STUB_PIDFILE")" 2>/dev/null || :; fi
}

conf() { printf '%s\n' "$@" >"$XDG_CONFIG_HOME/fbsd/fbsd.conf"; }

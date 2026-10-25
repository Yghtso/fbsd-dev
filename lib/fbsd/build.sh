# shellcheck shell=sh
# build.sh: run long guest jobs with a full log on the host, and read the
# serial console log.

# guest_logged log filter 'script'
#   Run a FreeBSD sh script in the guest. Its whole output goes to the host
#   file $log; only lines matching the extended regex $filter (empty: all
#   lines) are shown live. On failure, print the first error and the tail.
#   Returns the script's exit status.
guest_logged() {
	_log=$1 _filter=$2 _script=$3
	if is_dryrun; then
		guest_sh run "$_script"
		note "output saved to $_log"
		return 0
	fi
	mkdir -p "$(dirname -- "$_log")"
	_rcfile=$(mktemp)
	_t0=$(date +%s)
	info "full log: $_log"
	{
		_rc=0
		guest_sh run "$_script" </dev/null || _rc=$?
		echo "$_rc" >"$_rcfile"
	} 2>&1 | tee "$_log" | {
		if [ -n "$_filter" ]; then grep --line-buffered -E "$_filter" || :; else cat; fi
	}
	_rc=$(cat "$_rcfile")
	rm -f "$_rcfile"
	_secs=$(($(date +%s) - _t0))
	if [ "$_rc" -eq 0 ]; then
		info "done in $((_secs / 60))m$((_secs % 60))s"
	else
		log_failure "$_log"
		warn "failed (exit $_rc) after $((_secs / 60))m$((_secs % 60))s; full log: $_log"
	fi
	return "$_rc"
}

# log_failure log: print the first error line (with context) and the tail.
log_failure() {
	_first=$(grep -n -m 1 -E '(error:|Error code|^\*\*\* |fatal error|: not found$|Stop\.$)' "$1" |
		cut -d: -f1) || :
	if [ -n "$_first" ]; then
		printf '%s\n' "---- first error (line $_first) ----" >&2
		sed -n "$((_first > 3 ? _first - 3 : 1)),$((_first + 3))p" "$1" >&2
	fi
	printf '%s\n' "---- last 25 lines ----" >&2
	tail -n 25 "$1" >&2
}

# console_size: current size in bytes of the serial console log (0 if none).
console_size() {
	if [ -f "$FBSD_CONSOLE_LOG" ]; then wc -c <"$FBSD_CONSOLE_LOG" | tr -d ' '; else echo 0; fi
}

# console_since offset: console output written after byte offset, without
# carriage returns and terminal escapes.
console_since() {
	[ -f "$FBSD_CONSOLE_LOG" ] || return 0
	tail -c "+$(($1 + 1))" "$FBSD_CONSOLE_LOG" |
		tr -d '\r' | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g'
}

# panic_report offset: if the console shows a panic since offset, print the
# panic line, the backtrace and the dump lines, and return 0; else return 1.
panic_report() {
	_c=$(console_since "$1")
	printf '%s\n' "$_c" | grep -q '^panic: ' || return 1
	printf '%s\n' "$_c" | awk '
		/^panic: / { p = 1 }
		p && n < 40 { print; n++ }
		/^Dump complete|^Dump failed|^Automatic reboot|^db> / { if (p) print }
	' | awk '!seen[$0]++'
	return 0
}

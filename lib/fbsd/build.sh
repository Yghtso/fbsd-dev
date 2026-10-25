# shellcheck shell=sh
# build.sh: run long guest jobs with a full log on the host, and read the
# serial console log.

# Long guest jobs run detached under daemon(8), so a dropped ssh connection
# (or a restarted host shell) does not kill them. One job at a time, in
# FBSD_GUEST_JOBDIR: script.sh, log (all output), rc (exit status, written
# last), hostlog (where the host copy lives). The host polls the log.
FBSD_GUEST_JOBDIR=/var/tmp/fbsd-job

# guest_logged log filter 'script'
#   Start a FreeBSD sh script as a detached guest job and follow it: the
#   whole output is copied to the host file $log; only lines matching the
#   extended regex $filter (empty: all lines) are shown live. On failure,
#   print the first error and the tail. Returns the script's exit status.
guest_logged() {
	_log=$1 _filter=$2 _script=$3
	# shellcheck disable=SC2016 # expanded by the guest shell
	_start="d=$FBSD_GUEST_JOBDIR hostlog=$(shquote "$_log")
script=$(shquote "$_script")"'
set -eu
if [ -f "$d/pid" ] && [ ! -f "$d/rc" ] && pgrep -F "$d/pid" >/dev/null 2>&1; then
	echo "fbsd: a guest job is already running (host log: $(cat "$d/hostlog"))" >&2
	exit 75
fi
rm -rf "$d"
mkdir -p "$d"
printf "%s\n" "$script" >"$d/script.sh"
printf "%s\n" "$hostlog" >"$d/hostlog"
daemon -f -p "$d/pid" -o "$d/log" /bin/sh -c "/bin/sh $d/script.sh; echo \$? >$d/rc.tmp; mv $d/rc.tmp $d/rc"'
	if is_dryrun && ! dry_full; then
		show_guest "as $FBSD_SSH_USER, detached with daemon(8) in $FBSD_GUEST_JOBDIR" "$_script"
		note "output copied to $_log every 3 s until the job ends (-nn shows the launcher)"
		return 0
	elif is_dryrun; then
		guest_sh run "$_start"
		note "follow: copy $FBSD_GUEST_JOBDIR/log to $_log every 3 s until $FBSD_GUEST_JOBDIR/rc exists"
		return 0
	fi
	mkdir -p "$(dirname -- "$_log")"
	: >"$_log"
	info "full log: $_log (the job runs detached; reattach with: fbsd build -a)"
	guest_sh run "$_start" </dev/null || return $?
	guest_follow "$_log" "$_filter"
}

# guest_follow log filter: copy the guest job's log to $log as it grows,
# show matching lines, return the job's exit status once it has one.
guest_follow() {
	_log=$1 _filter=$2
	_t0=$(date +%s) _fails=0
	_chunk=$(mktemp)
	while :; do
		_rc=$(guest_ssh probe "cat $FBSD_GUEST_JOBDIR/rc 2>/dev/null" 2>/dev/null) || _rc=''
		_size=$(wc -c <"$_log" | tr -d ' ')
		if guest_ssh probe "tail -c +$((_size + 1)) $FBSD_GUEST_JOBDIR/log" >"$_chunk" 2>/dev/null; then
			_fails=0
			cat "$_chunk" >>"$_log"
			if [ -n "$_filter" ]; then grep -E "$_filter" "$_chunk" || :; else cat "$_chunk"; fi
		else
			_fails=$((_fails + 1))
			[ "$_fails" -lt 60 ] || {
				rm -f "$_chunk"
				die "lost contact with the guest for 3 minutes; the job may still run" "fbsd build -a"
			}
		fi
		case $_rc in '' | *[!0-9]*) sleep 3 ;; *) break ;; esac
	done
	rm -f "$_chunk"
	_secs=$(($(date +%s) - _t0))
	if [ "$_rc" -eq 0 ]; then
		info "done in $((_secs / 60))m$((_secs % 60))s"
	else
		log_failure "$_log"
		warn "failed (exit $_rc) after $((_secs / 60))m$((_secs % 60))s; full log: $_log"
	fi
	return "$_rc"
}

# guest_attach: follow a job started earlier (after a host disconnect).
guest_attach() {
	_hl=$(guest_ssh probe "cat $FBSD_GUEST_JOBDIR/hostlog" 2>/dev/null) ||
		die "no guest job to attach to" "start one with fbsd build"
	[ -n "$_hl" ] || die "no guest job to attach to"
	mkdir -p "$(dirname -- "$_hl")"
	: >"$_hl"
	info "attaching; full log: $_hl"
	guest_follow "$_hl" '^>>> '
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
	# A panic can land right after a "login: " prompt on the same line.
	_c=$(printf '%s\n' "$_c" | sed 's/^.*login: panic: /panic: /')
	printf '%s\n' "$_c" | grep -q '^panic: ' || return 1
	# From the first "panic:" to the dump/reboot/ddb line (at most 60 lines).
	printf '%s\n' "$_c" | awk '
		/^panic: / { p = 1 }
		p { print; n++ }
		p && (/^Automatic reboot|^db> / || n >= 60) { exit }
	'
	return 0
}

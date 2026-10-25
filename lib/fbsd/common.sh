# shellcheck shell=sh
# common.sh: logging, quoting and the dry-run aware command runner.
# Sourced by bin/fbsd and every libexec/fbsd/fbsd-* script.

: "${FBSD_DRYRUN:=0}"
: "${FBSD_VERBOSE:=0}"
FBSD_PROG=${FBSD_PROG:-fbsd}

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
	_c_info=$(printf '\033[1;34m') _c_warn=$(printf '\033[1;33m')
	_c_err=$(printf '\033[1;31m') _c_off=$(printf '\033[0m')
else
	_c_info='' _c_warn='' _c_err='' _c_off=''
fi

info() { printf '%s==>%s %s\n' "$_c_info" "$_c_off" "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$_c_warn" "$_c_off" "$*" >&2; }

# die message [hint]: print an error (and a hint on how to fix it), exit 1.
die() {
	printf '%serror:%s %s\n' "$_c_err" "$_c_off" "$1" >&2
	[ $# -lt 2 ] || printf '  hint: %s\n' "$2" >&2
	exit 1
}

# usage_error message: bad invocation, exit 2.
usage_error() {
	printf '%serror:%s %s (see -h)\n' "$_c_err" "$_c_off" "$1" >&2
	exit 2
}

is_dryrun() { [ "$FBSD_DRYRUN" = 1 ]; }

# shquote arg...: print the arguments as one line that a POSIX shell parses
# back into the same words.
shquote() {
	_sep=''
	for _a in "$@"; do
		case $_a in
		'' | *[!A-Za-z0-9_@%+=:,./-]*)
			printf "%s'%s'" "$_sep" "$(printf '%s' "$_a" | sed "s/'/'\\\\''/g")"
			;;
		*) printf '%s%s' "$_sep" "$_a" ;;
		esac
		_sep=' '
	done
	printf '\n'
}

# show_cmd text: how a command is displayed. With -n it goes to stdout (so a
# dry run can be saved as a script); with -v it goes to stderr.
show_cmd() {
	if is_dryrun; then
		printf '%s\n' "$1"
	elif [ "$FBSD_VERBOSE" = 1 ]; then
		printf '+ %s\n' "$1" >&2
	fi
}

# run cmd [args...]: every state-changing command goes through here.
# Prints it under -n/-v; executes it unless -n.
run() {
	show_cmd "$(shquote "$@")"
	is_dryrun || "$@"
}

# run_exec cmd [args...]: like run, but replaces the current process.
run_exec() {
	show_cmd "$(shquote "$@")"
	is_dryrun && exit 0
	exec "$@"
}

# note text: a comment line in dry-run output for steps that are not a single
# command (waits, loops).
note() {
	if is_dryrun; then
		printf '# %s\n' "$*"
	fi
}

# need_cmd name package: fail with the pacman hint if a host tool is missing.
need_cmd() {
	command -v "$1" >/dev/null 2>&1 ||
		die "$1 not found on the host" "install it: sudo pacman -S $2"
}

# is_uint value
is_uint() {
	case $1 in '' | *[!0-9]*) return 1 ;; esac
}

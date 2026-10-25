# shellcheck shell=sh
# guest.sh: SSH to the guest through one shared ControlMaster connection.
#
# The toolkit uses its own options instead of ~/.ssh/config, and its own
# known_hosts file (keyed by HostKeyAlias), so recreating the VM never clashes
# with your global known_hosts.

# guest_ssh mode [remote args...]
#   mode run   : run through `run` (shown with -n/-v, skipped with -n)
#   mode tty   : like run, with a terminal (for sudo password prompts)
#   mode exec  : like run, but exec ssh (interactive use)
#   mode probe : quiet, non-interactive, short timeout; always executes
guest_ssh() {
	_mode=$1
	shift
	if is_dryrun && ! dry_full && [ "$_mode" != probe ]; then
		show_guest "as $FBSD_SSH_USER" "$*"
		[ "$_mode" != exec ] || exit 0
		return 0
	fi
	set -- -p "$FBSD_SSH_PORT" -i "$FBSD_SSH_KEY" -o IdentitiesOnly=yes \
		-o ControlMaster=auto -o "ControlPath=$FBSD_VMRUN/ssh-%C" \
		-o ControlPersist=10m -o "HostKeyAlias=$FBSD_VM_NAME" \
		-o "UserKnownHostsFile=$FBSD_WORKDIR/known_hosts" \
		-o StrictHostKeyChecking=accept-new \
		-o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
		"$FBSD_SSH_USER@127.0.0.1" "$@"
	case $_mode in
	run) run ssh "$@" ;;
	tty) run ssh -t "$@" ;;
	exec) run_exec ssh "$@" ;;
	probe)
		# ssh uses the first value given for an option, so these win.
		ssh -o BatchMode=yes -o ConnectTimeout=3 -o ControlMaster=no \
			-o LogLevel=ERROR "$@" </dev/null
		;;
	esac
}

# guest_sh mode 'script': run a FreeBSD /bin/sh script in the guest, whatever
# the user's login shell is.
guest_sh() {
	if is_dryrun && ! dry_full; then
		show_guest "as $FBSD_SSH_USER" "$2"
		return 0
	fi
	guest_ssh "$1" "/bin/sh -c $(shquote "$2")"
}

# guest_root_sh mode 'script': the same, as root through FBSD_GUEST_SU.
guest_root_sh() {
	if is_dryrun && ! dry_full; then
		show_guest "as root ($FBSD_GUEST_SU)" "$2"
		return 0
	fi
	guest_ssh "$1" "$FBSD_GUEST_SU /bin/sh -c $(shquote "$2")"
}

# show_guest who text: readable dry-run form of a guest command or script.
show_guest() {
	case $2 in
	*'
'*)
		printf '# ---- guest script, %s (FreeBSD sh) ----\n%s\n# ---- end of guest script ----\n' "$1" "$2"
		;;
	*) printf 'guest (%s)$ %s\n' "$1" "$2" ;;
	esac
}

guest_reachable() { guest_ssh probe true >/dev/null 2>&1; }

# wait_ssh timeout: wait until sshd answers.
wait_ssh() {
	note "wait up to $1 s for sshd on 127.0.0.1:$FBSD_SSH_PORT"
	is_dryrun && return 0
	_t=0
	while ! guest_reachable; do
		_t=$((_t + 2))
		[ "$_t" -lt "$1" ] || return 1
		sleep 2
	done
}

# wait_ssh_down timeout: wait until sshd stops answering (the guest is going
# down), so a reboot is not mistaken for the old system still being up.
wait_ssh_down() {
	note "wait up to $1 s for sshd to go away (guest shutting down)"
	is_dryrun && return 0
	_t=0
	while guest_reachable; do
		_t=$((_t + 2))
		[ "$_t" -lt "$1" ] || return 1
		sleep 2
	done
}

# guest_reboot: shutdown -r now through FBSD_GUEST_SU, wait for the guest to
# go down and for sshd to come back (FBSD_BOOT_TIMEOUT).
guest_reboot() {
	# ssh exits 255 when the guest drops the connection: expected here.
	guest_ssh run "$FBSD_GUEST_SU shutdown -r now" || :
	wait_ssh_down 180 || die "the guest did not go down within 180 s" "fbsd vm console"
	wait_ssh "$FBSD_BOOT_TIMEOUT" ||
		die "sshd did not come back within $FBSD_BOOT_TIMEOUT s" "fbsd vm log -t 50"
}

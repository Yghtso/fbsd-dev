# shellcheck shell=sh
# guest.sh: SSH to the guest through one shared ControlMaster connection.
#
# The toolkit uses its own options instead of ~/.ssh/config, and its own
# known_hosts file (keyed by HostKeyAlias), so recreating the VM never clashes
# with your global known_hosts.

# guest_ssh mode [remote args...]
#   mode run   : run through `run` (shown with -n/-v, skipped with -n)
#   mode exec  : like run, but exec ssh (interactive use)
#   mode probe : quiet, non-interactive, short timeout; always executes
guest_ssh() {
	_mode=$1
	shift
	set -- -p "$FBSD_SSH_PORT" -i "$FBSD_SSH_KEY" -o IdentitiesOnly=yes \
		-o ControlMaster=auto -o "ControlPath=$FBSD_VMRUN/ssh-%C" \
		-o ControlPersist=10m -o "HostKeyAlias=$FBSD_VM_NAME" \
		-o "UserKnownHostsFile=$FBSD_WORKDIR/known_hosts" \
		-o StrictHostKeyChecking=accept-new \
		"$FBSD_SSH_USER@127.0.0.1" "$@"
	case $_mode in
	run) run ssh "$@" ;;
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
	guest_ssh "$1" "/bin/sh -c $(shquote "$2")"
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

# shellcheck shell=sh
# Variables set here are read by the scripts that source this file.
# shellcheck disable=SC2034
# config.sh: load fbsd.conf with precedence environment > file > defaults.
#
# The file is plain KEY=value lines, sourced with `.`. Defaults are applied
# after the file, so a value in the file may refer to $HOME or $XDG_* but not
# to another FBSD_* key that is left at its default.

FBSD_KEYS='FBSD_VM_NAME FBSD_WORKDIR FBSD_DISK FBSD_RUNDIR FBSD_LOGDIR
FBSD_CPUS FBSD_MEM FBSD_FIRMWARE FBSD_OVMF_CODE FBSD_OVMF_VARS_TEMPLATE
FBSD_OVMF_VARS FBSD_SSH_PORT FBSD_SSH_USER FBSD_SSH_KEY FBSD_GDB_PORT
FBSD_GUEST_SU FBSD_SRC FBSD_OBJ FBSD_KERNCONF FBSD_TESTKERNEL FBSD_JOBS
FBSD_MAKE_ARGS FBSD_BOOT_TIMEOUT FBSD_SHUTDOWN_TIMEOUT FBSD_SRC_URL
FBSD_GUEST_ARC_MAX FBSD_IMAGE_URL FBSD_IMAGE_NAME FBSD_DISK_SIZE
FBSD_GUEST_PACKAGES FBSD_FIRSTBOOT_TIMEOUT'

fbsd_config_file() {
	printf '%s\n' "${FBSD_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/fbsd/fbsd.conf}"
}

# Sets every FBSD_* key, plus FBSD_FROM_ENV / FBSD_FROM_FILE (space separated
# key lists, used by `fbsd config`).
fbsd_load_config() {
	_saved=''
	for _k in $FBSD_KEYS; do
		if _v=$(printenv "$_k"); then
			_saved="$_saved$_k=$_v
"
		fi
		unset "$_k"
	done
	# Mark every key for export before sourcing, so plain KEY=value lines in
	# the file become visible to printenv (this avoids eval) and to children.
	# shellcheck disable=SC2086,SC2163 # FBSD_KEYS is a fixed word list
	export $FBSD_KEYS

	FBSD_CONFIG_FILE=$(fbsd_config_file)
	FBSD_FROM_FILE=''
	if [ -f "$FBSD_CONFIG_FILE" ]; then
		# shellcheck source=/dev/null
		. "$FBSD_CONFIG_FILE"
		for _k in $FBSD_KEYS; do
			if [ -n "$(getvar "$_k")" ]; then
				FBSD_FROM_FILE="$FBSD_FROM_FILE $_k"
			fi
		done
	elif [ -n "${FBSD_CONFIG:-}" ]; then
		die "config file not found: $FBSD_CONFIG_FILE" "check the -C argument"
	fi

	FBSD_FROM_ENV=''
	while IFS= read -r _line; do
		[ -n "$_line" ] || continue
		export "${_line%%=*}=${_line#*=}"
		FBSD_FROM_ENV="$FBSD_FROM_ENV ${_line%%=*}"
	done <<EOF
$_saved
EOF

	: "${FBSD_VM_NAME:=fbsd-dev}"
	: "${FBSD_WORKDIR:=${XDG_DATA_HOME:-$HOME/.local/share}/fbsd}"
	: "${FBSD_DISK:=$FBSD_WORKDIR/$FBSD_VM_NAME.qcow2}"
	: "${FBSD_RUNDIR:=${XDG_RUNTIME_DIR:-/tmp/fbsd-$(id -u)}/fbsd}"
	: "${FBSD_LOGDIR:=$FBSD_WORKDIR/log}"
	: "${FBSD_CPUS:=8}"
	: "${FBSD_MEM:=8G}"
	: "${FBSD_FIRMWARE:=uefi}"
	: "${FBSD_OVMF_CODE:=/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
	: "${FBSD_OVMF_VARS_TEMPLATE:=/usr/share/edk2/x64/OVMF_VARS.4m.fd}"
	: "${FBSD_OVMF_VARS:=$FBSD_WORKDIR/$FBSD_VM_NAME.OVMF_VARS.fd}"
	: "${FBSD_SSH_PORT:=2222}"
	: "${FBSD_SSH_USER:=${USER:-$(id -un)}}"
	: "${FBSD_SSH_KEY:=$HOME/.ssh/id_ed25519}"
	: "${FBSD_GDB_PORT:=1234}"
	: "${FBSD_GUEST_SU:=sudo}"
	: "${FBSD_SRC:=/usr/src}"
	: "${FBSD_OBJ:=/usr/obj}"
	: "${FBSD_KERNCONF:=GENERIC}"
	: "${FBSD_TESTKERNEL:=kernel.test}"
	: "${FBSD_JOBS:=$FBSD_CPUS}"
	: "${FBSD_MAKE_ARGS:=}"
	: "${FBSD_BOOT_TIMEOUT:=300}"
	: "${FBSD_SHUTDOWN_TIMEOUT:=120}"
	: "${FBSD_SRC_URL:=https://git.freebsd.org/src.git}"
	: "${FBSD_GUEST_ARC_MAX:=2147483648}"
	: "${FBSD_IMAGE_URL:=https://download.freebsd.org/snapshots/VM-IMAGES/16.0-CURRENT/amd64/Latest}"
	: "${FBSD_IMAGE_NAME:=FreeBSD-16.0-CURRENT-amd64-BASIC-CLOUDINIT-zfs.qcow2.xz}"
	: "${FBSD_DISK_SIZE:=86G}"
	: "${FBSD_GUEST_PACKAGES:=sudo git perl5}"
	: "${FBSD_FIRSTBOOT_TIMEOUT:=3600}"

	for _k in FBSD_CPUS FBSD_SSH_PORT FBSD_GDB_PORT FBSD_JOBS \
		FBSD_BOOT_TIMEOUT FBSD_SHUTDOWN_TIMEOUT FBSD_GUEST_ARC_MAX FBSD_FIRSTBOOT_TIMEOUT; do
		is_uint "$(getvar "$_k")" ||
			die "$_k must be a number, got '$(getvar "$_k")'" \
				"fix it in $FBSD_CONFIG_FILE or the environment"
	done
	case $FBSD_FIRMWARE in
	bios | uefi) ;;
	*) die "FBSD_FIRMWARE must be 'bios' or 'uefi', got '$FBSD_FIRMWARE'" ;;
	esac
	case $FBSD_GUEST_SU in
	sudo | doas) ;;
	*) die "FBSD_GUEST_SU must be 'sudo' or 'doas', got '$FBSD_GUEST_SU'" ;;
	esac
	case $FBSD_VM_NAME in
	'' | *[!A-Za-z0-9_.-]*) die "FBSD_VM_NAME may only contain A-Z a-z 0-9 _ . -" ;;
	esac

	# Derived paths, used by the scripts that source this file.
	FBSD_VMRUN=$FBSD_RUNDIR/$FBSD_VM_NAME
	FBSD_PIDFILE=$FBSD_VMRUN/qemu.pid
	FBSD_SERIAL_SOCK=$FBSD_VMRUN/serial.sock
	FBSD_MONITOR_SOCK=$FBSD_VMRUN/monitor.sock
	FBSD_CONSOLE_LOG=$FBSD_LOGDIR/$FBSD_VM_NAME.console.log
}

# getvar KEY: print the value of the exported variable KEY ('' if unset).
getvar() {
	printenv "$1" 2>/dev/null || :
}

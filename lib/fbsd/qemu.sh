# shellcheck shell=sh
# qemu.sh: VM state probes and the QEMU command line.

# vm_pid: print the QEMU pid if the VM is running, else return 1.
# The pid is trusted only if that process was started with our pidfile, so a
# stale pidfile whose pid got reused is not mistaken for the VM.
vm_pid() {
	[ -r "$FBSD_PIDFILE" ] || return 1
	_pid=$(cat "$FBSD_PIDFILE" 2>/dev/null) || return 1
	is_uint "$_pid" || return 1
	kill -0 "$_pid" 2>/dev/null || return 1
	tr '\0' '\n' <"/proc/$_pid/cmdline" 2>/dev/null |
		grep -qxF -- "$FBSD_PIDFILE" || return 1
	printf '%s\n' "$_pid"
}

vm_running() { vm_pid >/dev/null; }

# port_in_use port: true if something listens on 127.0.0.1:port (or *:port).
port_in_use() {
	command -v ss >/dev/null 2>&1 || return 1
	ss -Hltn "( sport = :$1 )" 2>/dev/null | grep -q .
}

# qemu_up: start the VM in the background (through run, so -n shows it).
qemu_up() {
	set -- qemu-system-x86_64 \
		-name "$FBSD_VM_NAME" \
		-machine q35,accel=kvm -cpu host \
		-smp "$FBSD_CPUS" -m "$FBSD_MEM"
	if [ "$FBSD_FIRMWARE" = uefi ]; then
		set -- "$@" \
			-drive "if=pflash,format=raw,unit=0,readonly=on,file=$FBSD_OVMF_CODE" \
			-drive "if=pflash,format=raw,unit=1,file=$FBSD_OVMF_VARS"
	fi
	set -- "$@" \
		-drive "file=$FBSD_DISK,if=virtio,format=qcow2,cache=writeback"
	# First boot of `vm create` only: the cloud-init NoCloud seed.
	if [ -n "${FBSD_SEED_ISO:-}" ]; then
		set -- "$@" -drive "file=$FBSD_SEED_ISO,media=cdrom,readonly=on,format=raw"
	fi
	set -- "$@" \
		-netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$FBSD_SSH_PORT-:22" \
		-device virtio-net-pci,netdev=n0 \
		-device virtio-rng-pci \
		-chardev "socket,id=ser0,path=$FBSD_SERIAL_SOCK,server=on,wait=off,logfile=$FBSD_CONSOLE_LOG,logappend=on" \
		-serial chardev:ser0 \
		-monitor "unix:$FBSD_MONITOR_SOCK,server=on,wait=off" \
		-gdb "tcp:127.0.0.1:$FBSD_GDB_PORT" \
		-display none \
		-daemonize -pidfile "$FBSD_PIDFILE"
	run "$@"
}

# monitor_cmd 'hmp command': send one command to the QEMU human monitor.
monitor_cmd() {
	show_cmd "printf '%s\\n' $(shquote "$1") | socat - $(shquote "UNIX-CONNECT:$FBSD_MONITOR_SOCK")"
	is_dryrun && return 0
	printf '%s\n' "$1" | socat - "UNIX-CONNECT:$FBSD_MONITOR_SOCK" >/dev/null
}

# socket_attach socket: interactive raw attach, Ctrl-] detaches.
socket_attach() {
	need_cmd socat socat
	run_exec socat -,raw,echo=0,escape=0x1d "UNIX-CONNECT:$1"
}

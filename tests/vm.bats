#!/usr/bin/env bats
load helper

@test "vm up -n prints the qemu command and changes nothing" {
	run "$FBSD" -n vm up
	[ "$status" -eq 0 ]
	[[ $output == *"qemu-system-x86_64 -name fbsd-dev -machine q35,accel=kvm -cpu host -smp 8 -m 8G"* ]]
	[[ $output == *"hostfwd=tcp:127.0.0.1:2222-:22"* ]]
	[[ $output == *"-gdb tcp:127.0.0.1:1234"* ]]
	[[ $output == *"-daemonize -pidfile $XDG_RUNTIME_DIR/fbsd/fbsd-dev/qemu.pid"* ]]
	[ ! -s "$STUB_LOG" ]
	[ ! -e "$XDG_RUNTIME_DIR/fbsd" ]
}

@test "uefi adds pflash drives and copies the vars template once" {
	run "$FBSD" -n vm up
	[[ $output == *"if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd"* ]]
	[[ $output == *"cp /usr/share/edk2/x64/OVMF_VARS.4m.fd $XDG_DATA_HOME/fbsd/fbsd-dev.OVMF_VARS.fd"* ]]
	: >"$XDG_DATA_HOME/fbsd/fbsd-dev.OVMF_VARS.fd"
	run "$FBSD" -n vm up
	[[ $output != *"cp "* ]]
}

@test "bios has no pflash" {
	FBSD_FIRMWARE=bios run "$FBSD" -n vm up
	[ "$status" -eq 0 ]
	[[ $output != *pflash* ]]
}

@test "config values reach the command line" {
	conf FBSD_CPUS=2 FBSD_MEM=3G FBSD_SSH_PORT=2022 FBSD_GDB_PORT=4321
	run "$FBSD" -n vm up
	[[ $output == *"-smp 2 -m 3G"* ]]
	[[ $output == *"hostfwd=tcp:127.0.0.1:2022-:22"* ]]
	[[ $output == *"-gdb tcp:127.0.0.1:4321"* ]]
}

@test "missing disk fails with a hint" {
	rm "$XDG_DATA_HOME/fbsd/fbsd-dev.qcow2"
	run "$FBSD" vm up
	[ "$status" -eq 1 ]
	[[ $output == *"disk not found"* ]]
	[[ $output == *"hint:"* ]]
}

@test "up, up again, status, down: idempotent lifecycle with stubs" {
	[ -r /dev/kvm ] && [ -w /dev/kvm ] || skip "no /dev/kvm access"
	FBSD_FIRMWARE=bios FBSD_SSH_PORT=52222 FBSD_GDB_PORT=51234 run "$FBSD" vm up
	[ "$status" -eq 0 ]
	[ "$(grep -c '^-name' "$STUB_LOG")" -eq 1 ]
	FBSD_FIRMWARE=bios run "$FBSD" vm up
	[ "$status" -eq 0 ]
	[[ $output == *"already running"* ]]
	[ "$(grep -c '^-name' "$STUB_LOG")" -eq 1 ]
	run "$FBSD" vm status
	[ "$status" -eq 0 ]
	[[ $output == *"running (pid"*"sshd down"* ]]
	run "$FBSD" vm down
	[ "$status" -eq 0 ]
	grep -q 'socat - UNIX-CONNECT:.*monitor.sock <<< system_powerdown' "$STUB_LOG"
	run "$FBSD" vm status
	[ "$status" -eq 3 ]
	run "$FBSD" vm down
	[ "$status" -eq 0 ]
	[[ $output == *"already stopped"* ]]
}

@test "a stale pidfile with a foreign pid is not taken for the VM" {
	mkdir -p "$XDG_RUNTIME_DIR/fbsd/fbsd-dev"
	echo $$ >"$STUB_PIDFILE"
	run "$FBSD" vm status
	[ "$status" -eq 3 ]
	rm "$STUB_PIDFILE"
}

@test "vm down -f -n on a stopped VM does nothing" {
	run "$FBSD" -n vm down -f
	[ "$status" -eq 0 ]
	[[ $output == *"not running; nothing to do"* ]]
}

@test "options are checked per subcommand" {
	run "$FBSD" vm up -f
	[ "$status" -eq 2 ]
	run "$FBSD" vm log -t abc
	[ "$status" -eq 2 ]
}

@test "vm console -n shows the socat attach" {
	run "$FBSD" -n vm console
	[[ $output == *"socat -,raw,echo=0,escape=0x1d UNIX-CONNECT:$XDG_RUNTIME_DIR/fbsd/fbsd-dev/serial.sock"* ]]
}

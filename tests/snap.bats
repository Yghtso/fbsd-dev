#!/usr/bin/env bats
load helper

# These use the real qemu-img on a small scratch image.
setup_file() { command -v qemu-img >/dev/null || skip "qemu-img not installed"; }

mkdisk() { qemu-img create -q -f qcow2 "$XDG_DATA_HOME/fbsd/fbsd-dev.qcow2" 16M; }

@test "save, list, refuse duplicate, revert needs -f, delete" {
	mkdisk
	run "$FBSD" vm snap list
	[[ $output == *"no snapshots"* ]]
	run "$FBSD" vm snap save one
	[ "$status" -eq 0 ]
	run "$FBSD" vm snap save one
	[ "$status" -eq 1 ]
	[[ $output == *"already exists"* ]]
	run "$FBSD" vm snap list
	[[ $output == *" one "* ]]
	run "$FBSD" vm snap revert one
	[ "$status" -eq 1 ]
	[[ $output == *"add -f"* ]]
	run "$FBSD" vm snap revert -f one
	[ "$status" -eq 0 ]
	run "$FBSD" vm snap delete one
	[ "$status" -eq 1 ]
	run "$FBSD" vm snap delete -f one
	[ "$status" -eq 0 ]
	run "$FBSD" vm snap list
	[[ $output == *"no snapshots"* ]]
}

@test "save without a name uses a timestamp" {
	mkdisk
	run "$FBSD" -n vm snap save
	[[ $output == "qemu-img snapshot -c snap-"[0-9]*-[0-9]*" $XDG_DATA_HOME/fbsd/fbsd-dev.qcow2" ]]
}

@test "dry run changes nothing" {
	mkdisk
	run "$FBSD" -n vm snap save two
	[ "$output" = "qemu-img snapshot -c two $XDG_DATA_HOME/fbsd/fbsd-dev.qcow2" ]
	run "$FBSD" vm snap list
	[[ $output == *"no snapshots"* ]]
}

@test "bad names and a running VM are refused" {
	mkdisk
	run "$FBSD" vm snap save 'a b'
	[ "$status" -eq 2 ]
	run "$FBSD" vm snap save -- -x
	[ "$status" -eq 2 ]
	FBSD_FIRMWARE=bios FBSD_SSH_PORT=52222 FBSD_GDB_PORT=51234 "$FBSD" vm up
	run "$FBSD" vm snap save three
	[ "$status" -eq 1 ]
	[[ $output == *"VM fbsd-dev is running"* ]]
}

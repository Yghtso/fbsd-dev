#!/usr/bin/env bats
load helper

@test "ssh -n shows the full ssh command with ControlMaster" {
	run "$FBSD" -n ssh uname -a
	[ "$status" -eq 0 ]
	[[ $output == *"ssh -p 2222 -i $HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes -o ControlMaster=auto -o ControlPath=$XDG_RUNTIME_DIR/fbsd/fbsd-dev/ssh-%C"* ]]
	[[ $output == *"-o HostKeyAlias=fbsd-dev -o UserKnownHostsFile=$XDG_DATA_HOME/fbsd/known_hosts"* ]]
	[[ $output == *"yghtso@127.0.0.1 uname -a"* || $output == *"@127.0.0.1 uname -a"* ]]
	[ ! -s "$STUB_LOG" ]
}

@test "ssh passes arguments to the stub" {
	STUB_SSH_RC=0 run "$FBSD" ssh echo hi
	[ "$status" -eq 0 ]
	grep -q '^ssh .*@127.0.0.1 echo hi$' "$STUB_LOG"
}

@test "doctor with a stopped VM checks the host only" {
	run "$FBSD" doctor
	[[ $output == *"host:"* ]]
	[[ $output == *"guest checks skipped"* ]]
	[[ $output != *"guest:"* ]]
}

@test "doctor reports a missing disk as a failure" {
	rm "$XDG_DATA_HOME/fbsd/fbsd-dev.qcow2"
	run "$FBSD" doctor
	[ "$status" -eq 1 ]
	[[ $output == *"FAIL  disk not found"* ]]
}

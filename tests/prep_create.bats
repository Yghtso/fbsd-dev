#!/usr/bin/env bats
load helper

# shellcheck disable=SC2016 # literal $user from the guest script
@test "vm prep -n shows the root script and the clone" {
	run "$FBSD" -nn vm prep
	[ "$status" -eq 0 ]
	[[ $output == "ssh -t -p 2222 "* ]]
	[[ $output == *"sudo /bin/sh -c"* ]]
	[[ $output == *"bectl create"* ]]
	[[ $output == *"NOPASSWD: ALL"* ]]
	[[ $output == *"visudo -cq"* ]]
	[[ $output == *'sudoers.d/zz-fbsd-$user'* ]]
	[[ $output == *"chmod 0440"* ]]
	[[ $output == *"tolower("* ]]
	[[ $output != *"sysrc -f /boot/loader.conf"* ]]
	[[ $output == *"arc=2147483648"* ]]
	[[ $output == *"KbdInteractiveAuthentication no"* ]]
	[[ $output == *"url=https://git.freebsd.org/src.git"* ]]
	[ ! -s "$STUB_LOG" ]
}

@test "vm prep -S skips the clone, doas is honoured" {
	FBSD_GUEST_SU=doas run "$FBSD" -nn vm prep -S
	[[ $output == *"doas /bin/sh -c"* ]]
	[[ $output != *"git clone"* ]]
}

@test "vm prep refuses an odd user name" {
	FBSD_SSH_USER='a;b' run "$FBSD" -n vm prep
	[ "$status" -eq 1 ]
}

@test "vm create refuses to overwrite a disk without -f" {
	run "$FBSD" -n vm create
	[ "$status" -eq 1 ]
	[[ $output == *"disk already exists"* ]]
}

@test "vm create -n: download, verify, seed and first boot" {
	rm "$XDG_DATA_HOME/fbsd/fbsd-dev.qcow2"
	printf 'ssh-ed25519 AAAAtest me@host\n' >"$HOME/.ssh/id_ed25519.pub"
	run "$FBSD" -n vm create
	[ "$status" -eq 0 ]
	[[ $output == *"curl -fL --proto =https -o $XDG_DATA_HOME/fbsd/images/CHECKSUM.SHA256 https://download.freebsd.org/"* ]]
	[[ $output == *"BASIC-CLOUDINIT-zfs.qcow2.xz"* ]]
	[[ $output == *"qemu-img resize -f qcow2 "*" 86G"* ]]
	[[ $output == *'- "ssh-ed25519 AAAAtest me@host"'* ]]
	[[ $output == *'sudo: "ALL=(ALL) NOPASSWD:ALL"'* ]]
	[[ $output == *"ssh_pwauth: false"* ]]
	[[ $output == *'passwd: "*"'* ]]
	[[ $output != *lock_passwd* ]]
	[[ $output == *"pw usermod -n root -H 0"* ]]
	[[ $output == *"FreeBSD-16.0-CURRENT-amd64-BASIC-CLOUDINIT-zfs.qcow2.xz"* ]]
	[[ $output == *"-volid CIDATA"* ]]
	[[ $output == *"vm up -w"* ]]
	[ ! -e "$XDG_DATA_HOME/fbsd/images" ]
}

@test "vm create -P uses the plain image and no seed" {
	rm "$XDG_DATA_HOME/fbsd/fbsd-dev.qcow2"
	run "$FBSD" -n vm create -P
	[ "$status" -eq 0 ]
	[[ $output == *"FreeBSD-16.0-CURRENT-amd64-zfs.qcow2.xz"* ]]
	[[ $output != *xorriso* ]]
	[[ $output != *"vm up -w"* ]]
}

@test "the seed ISO is attached only when FBSD_SEED_ISO is set" {
	run "$FBSD" -n vm up
	[[ $output != *media=cdrom* ]]
	FBSD_SEED_ISO=/x/seed.iso run "$FBSD" -n vm up
	[[ $output == *"-drive file=/x/seed.iso,media=cdrom,readonly=on,format=raw"* ]]
}

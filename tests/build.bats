#!/usr/bin/env bats
# shellcheck disable=SC2016,SC1091 # literal guest code in patterns; libs sourced at runtime
load helper

# The guest scripts are checked as text: a dry run never contacts the guest.

@test "build world/kernel/subdir -n: unprivileged make in the guest" {
	run "$FBSD" -nn build world
	[ "$status" -eq 0 ]
	[[ $output == *"set -- -j8 buildworld"* ]]
	[[ $output == *'exec make "$@"'* ]]
	[[ $output != *"sudo"* ]]
	[[ $output == *"follow: copy /var/tmp/fbsd-job/log to $XDG_DATA_HOME/fbsd/log/build/"*"-world.log"* ]]
	[[ $output == *'daemon -f -p "$d/pid" -o "$d/log"'* ]]
	run "$FBSD" -nn build -k MYKERNEL -j 3 kernel -- -DNO_KERNELCLEAN
	[[ $output == *"set -- -j3 buildkernel KERNCONF=MYKERNEL -DNO_KERNELCLEAN"* ]]
	FBSD_MAKE_ARGS='-DWITHOUT_TESTS -s' run "$FBSD" -nn build sys/modules/if_vtnet
	[[ $output == *"dir=sys/modules/if_vtnet"* ]]
	[[ $output == *"set -- -j8 -DWITHOUT_TESTS -s"* ]]
}

@test "build rejects bad targets and kernel configs" {
	run "$FBSD" -n build ../etc
	[ "$status" -eq 2 ]
	run "$FBSD" -n build /usr/src
	[ "$status" -eq 2 ]
	run "$FBSD" -n build -k 'a b' kernel
	[ "$status" -eq 2 ]
	run "$FBSD" -n build
	[ "$status" -eq 2 ]
}

@test "build shows UPDATING news only once a build is recorded" {
	run "$FBSD" -n build world
	[[ $output == *"no previous build recorded"* ]]
	mkdir -p "$XDG_DATA_HOME/fbsd/state"
	echo 0123456789abcdef0123456789abcdef01234567 >"$XDG_DATA_HOME/fbsd/state/fbsd-dev.last-build-rev"
	run "$FBSD" -n build world
	[[ $output == *"prev=0123456789abcdef0123456789abcdef01234567"* ]]
	[[ $output == *'git diff --no-color "$prev" HEAD -- UPDATING'* ]]
}

@test "install world -n wraps beinstall.sh with NO_PKG_UPGRADE and a one-shot BE" {
	run "$FBSD" -nn install world -r
	[ "$status" -eq 0 ]
	[[ $output == *"sudo /bin/sh -s <<"* ]]
	[[ $output == *"env NO_PKG_UPGRADE=1 sh tools/build/beinstall.sh"* ]]
	[[ $output == *'FreeBSD-base: { enabled: no }'* ]]
	[[ $output == *'/etc/fbsd-world'* ]]
	[[ $output == *'bectl activate "$default"'* ]]
	[[ $output == *'bectl activate -t "$new"'* ]]
	[[ $output == *"sudo shutdown -r now"* ]]
	run "$FBSD" -nn install kernel
	[ "$status" -eq 2 ]
}

@test "ktest -n: KODIR, nextboot -k, reboot, report" {
	run "$FBSD" -nn ktest
	[ "$status" -eq 0 ]
	[[ $output == *'installkernel KERNCONF="$kernconf" INSTKERNNAME="$name"'* ]]
	[[ $output == *"name=kernel.test"* ]]
	[[ $output == *"'sudo nextboot -k kernel.test'"* ]]
	[[ $output == *"'sudo shutdown -r now'"* ]]
	[[ $output == *"kern.bootfile"* ]]
	[[ $output != *"debugger_on_panic=1"* ]]
}

@test "ktest --ddb sets debugger_on_panic for one boot; -I skips the install" {
	run "$FBSD" -nn ktest --ddb -I
	[ "$status" -eq 0 ]
	[[ $output == *"'sudo nextboot -k kernel.test -e debug.debugger_on_panic=1'"* ]]
	[[ $output != *installkernel* ]]
}

@test "ktest refuses to install over /boot/kernel" {
	FBSD_TESTKERNEL=kernel run "$FBSD" -n ktest
	[ "$status" -eq 1 ]
	[[ $output == *"other than 'kernel'"* ]]
}

@test "ktest -x runs a command after boot" {
	run "$FBSD" -nn ktest -I -x 'sudo sysctl debug.kdb.panic=1'
	[[ $output == *"'sudo sysctl debug.kdb.panic=1'"* ]]
	[[ $output == *"if the guest went down"* ]]
}

@test "test -n: kyua on installed /usr/tests, -i builds then installs" {
	run "$FBSD" -n test -i lib/libc/tests/string lib/libc/string
	[ "$status" -eq 0 ]
	[[ $output == *"cd /usr/tests"* ]]
	[[ $output == *'$kyua_su kyua test -k /usr/tests/Kyuafile "$@"'* ]]
	[[ $output == *"kyua_su=sudo"* ]]
	[[ $output == *"srcdirs=lib/libc/tests/string"* ]]
	[[ $output == *'make -C "$src/$d" -j"$jobs"'* ]]
	[[ $output == *'$su make -C "$src/$d" install'* ]]
	[[ $output == *"set -- lib/libc/string"* ]]
	run "$FBSD" -n test -u sys/kern
	[[ $output != *"kyua_su=sudo"* ]]
}

@test "test needs a path and rejects escapes" {
	run "$FBSD" -n test
	[ "$status" -eq 2 ]
	run "$FBSD" -n test ../etc
	[ "$status" -eq 2 ]
	run "$FBSD" -n test -i /etc sys/kern
	[ "$status" -eq 2 ]
}

@test "vm reboot -n" {
	run "$FBSD" -nn vm reboot
	[ "$status" -eq 0 ]
	[[ $output == *"'sudo shutdown -r now'"* ]]
	[[ $output == *"wait up to 180 s for sshd to go away"* ]]
}

@test "log_failure prints the first error and the tail" {
	. "$BATS_TEST_DIRNAME/../lib/fbsd/common.sh"
	. "$BATS_TEST_DIRNAME/../lib/fbsd/build.sh"
	printf '%s\n' a b c 'foo.c:3:1: error: expected ;' d e '*** Error code 1' f >"$T/l"
	# common.sh defines its own run(), so call directly instead of bats run
	output=$(log_failure "$T/l" 2>&1)
	[[ $output == *"first error (line 4)"* ]]
	[[ $output == *"foo.c:3:1: error: expected ;"* ]]
	[[ $output == *"last 25 lines"* ]]
}

@test "panic_report finds the panic and backtrace in the console log" {
	. "$BATS_TEST_DIRNAME/../lib/fbsd/common.sh"
	. "$BATS_TEST_DIRNAME/../lib/fbsd/build.sh"
	FBSD_CONSOLE_LOG=$T/console.log
	printf 'old boot\r\npanic: old\r\n' >"$FBSD_CONSOLE_LOG"
	off=$(wc -c <"$FBSD_CONSOLE_LOG")
	if panic_report "$off"; then false; fi
	printf 'booting\r\nFreeBSD/amd64 (freebsd) (ttyu0)\r\n\r\nlogin: panic: kdb_sysctl_panic\r\ncpuid = 1\r\nKDB: stack backtrace:\r\n#0 0xffff at kdb_backtrace+0x5d\r\nDump complete\r\nAutomatic reboot in 15 seconds\r\nBdsDxe: loading Boot0002\r\n' >>"$FBSD_CONSOLE_LOG"
	output=$(panic_report "$off")
	[[ $output == *"panic: kdb_sysctl_panic"* ]]
	[[ $output == *"kdb_backtrace"* ]]
	[[ $output == *"Dump complete"* ]]
	[[ $output != *"panic: old"* ]]
	[[ $output != *BdsDxe* ]]
}

@test "-n shows guest scripts as plain text, -nn and -n -v the ssh lines" {
	run "$FBSD" -n ktest -I
	[[ $output == *'guest (as yghtso)$ sudo nextboot -k kernel.test'* || $output == *'guest (as '*')$ sudo nextboot -k kernel.test'* ]]
	[[ $output != *"ssh -p"* ]]
	run "$FBSD" -n install world
	[[ $output == *"# ---- guest script, as "*"detached with daemon(8)"* ]]
	[[ $output == *$'\nsudo /bin/sh -s <<\'FBSD_ROOT\'\n'* ]]
	[[ $output == *$'\nFBSD_ROOT\n# ---- end of guest script ----'* ]]
	run "$FBSD" -nn ktest -I
	[[ $output == *"ssh -p 2222 "* ]]
	run "$FBSD" -n -v ktest -I
	[[ $output == *"ssh -p 2222 "* ]]
	run "$FBSD" ktest -n -I
	[[ $output != *"ssh -p"* ]]
}

@test "vm prep -n shows the root script readably" {
	run "$FBSD" -n vm prep -S
	[ "$status" -eq 0 ]
	[[ $output == *"# ---- guest script, as root (sudo) (FreeBSD sh) ----"* ]]
	[[ $output == *"ntpd_enable=YES ntpd_sync_on_start=YES dumpon_flags=-Z"* ]]
	[[ $output == *'loader_set debug.debugger_on_panic 0'* ]]
}

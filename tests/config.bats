#!/usr/bin/env bats
load helper

@test "defaults follow XDG dirs" {
	run "$FBSD" config
	[ "$status" -eq 0 ]
	[[ $output == *"FBSD_DISK=$XDG_DATA_HOME/fbsd/fbsd-dev.qcow2	# default"* ]]
	[[ $output == *"FBSD_RUNDIR=$XDG_RUNTIME_DIR/fbsd	# default"* ]]
	[[ $output == *"FBSD_FIRMWARE=uefi	# default"* ]]
}

@test "file overrides default, env overrides file" {
	conf 'FBSD_CPUS=2' 'FBSD_MEM=4G'
	FBSD_CPUS=6 run "$FBSD" config
	[ "$status" -eq 0 ]
	[[ $output == *"FBSD_CPUS=6	# env"* ]]
	[[ $output == *"FBSD_MEM=4G	# file"* ]]
	[[ $output == *"FBSD_JOBS=6	# default"* ]]
}

@test "values with spaces and quotes survive" {
	conf "FBSD_MAKE_ARGS='-DNO_CLEAN WITHOUT_TESTS=yes'"
	run "$FBSD" config
	[[ $output == *"FBSD_MAKE_ARGS='-DNO_CLEAN WITHOUT_TESTS=yes'	# file"* ]]
}

@test "-C selects another file, a missing one is an error" {
	printf 'FBSD_CPUS=3\n' >"$BATS_TEST_TMPDIR/alt.conf"
	run "$FBSD" -C "$BATS_TEST_TMPDIR/alt.conf" config
	[[ $output == *"FBSD_CPUS=3	# file"* ]]
	run "$FBSD" -C /nonexistent config
	[ "$status" -eq 1 ]
	[[ $output == *"config file not found"* ]]
}

@test "bad values are rejected" {
	FBSD_CPUS=lots run "$FBSD" config
	[ "$status" -eq 1 ]
	[[ $output == *"FBSD_CPUS must be a number"* ]]
	FBSD_FIRMWARE=coreboot run "$FBSD" config
	[ "$status" -eq 1 ]
	FBSD_VM_NAME='a/b' run "$FBSD" config
	[ "$status" -eq 1 ]
}

# shellcheck disable=SC2016 # a literal $HOME is part of the test
@test "shquote output parses back to the same words" {
	# shellcheck source=lib/fbsd/common.sh
	. "$BATS_TEST_DIRNAME/../lib/fbsd/common.sh"
	line=$(shquote a 'b c' "it's" '' '$HOME' 'x"y')
	eval "set -- $line"
	[ "$#" -eq 6 ]
	[ "$2" = 'b c' ] && [ "$3" = "it's" ] && [ "$4" = '' ] && [ "$5" = '$HOME' ] && [ "$6" = 'x"y' ]
}

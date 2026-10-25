#!/usr/bin/env bats
load helper

@test "help lists every command with its summary" {
	run "$FBSD" help
	[ "$status" -eq 0 ]
	[[ $output == *"vm "*"start, stop"* ]]
	[[ $output == *"doctor "* ]]
	[[ $output == *"ssh "* ]]
	[[ $output == *"config "* ]]
}

@test "no command is a usage error" {
	run "$FBSD"
	[ "$status" -eq 2 ]
}

@test "unknown command fails with a hint" {
	run "$FBSD" frobnicate
	[ "$status" -eq 1 ]
	[[ $output == *"unknown command: frobnicate"* ]]
	[[ $output == *"hint:"* ]]
}

@test "command names with odd characters are rejected" {
	run "$FBSD" '../../bin/sh'
	[ "$status" -eq 2 ]
}

@test "nested lookup falls back to the group script" {
	run "$FBSD" vm bogus
	[ "$status" -eq 2 ]
	[[ $output == *"unknown vm subcommand: bogus"* ]]
}

@test "every command supports -h" {
	for c in config doctor ssh vm "vm snap" "vm prep" "vm create" build install ktest test; do
		# shellcheck disable=SC2086 # "vm snap" must split into two words
		run "$FBSD" $c -h
		[ "$status" -eq 0 ]
		[[ $output == *"usage: fbsd $c"* ]]
		[[ $output == *"Examples:"* ]]
	done
}

@test "global -n and command -n give the same dry run" {
	a=$("$FBSD" -n vm up)
	b=$("$FBSD" vm up -n)
	[ "$a" = "$b" ]
}

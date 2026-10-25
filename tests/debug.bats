#!/usr/bin/env bats
# shellcheck disable=SC2016 # literal guest code in patterns
load helper

@test "gdb -n: symbols from the guest, then gdb on the gdbstub" {
	command -v gdb >/dev/null || skip "gdb not installed"
	run "$FBSD" -n gdb -x bt -x 'p version'
	[ "$status" -eq 0 ]
	[[ $output == *"tar -C /usr/lib/debug/boot/"*"-cf - kernel.debug kernel-gdb.py gdb"* ]]
	[[ $output == *"gdb -batch -q -ex 'set debuginfod enabled off'"* ]]
	[[ $output == *"-ex 'target remote 127.0.0.1:1234' -ex bt -ex 'p version' -ex detach"* ]]
	run "$FBSD" -n gdb -S
	[[ $output == *"git -C /usr/src archive"*" sys"* ]]
	[[ $output == *"set substitute-path /usr/src $XDG_DATA_HOME/fbsd/src/"* ]]
	run "$FBSD" -n gdb -k 'a/b'
	[ "$status" -eq 2 ]
}

@test "crash -n: list, summary, kgdb with commands on stdin" {
	run "$FBSD" -n crash -l
	[ "$status" -eq 0 ]
	[[ $output == *"guest script, as root (sudo)"* ]]
	[[ $output == *'Panic String'* ]]
	run "$FBSD" -n crash -s 3
	[[ $output == *"n=3 mode=summary"* ]]
	run "$FBSD" -n crash -c bt -c 'info threads'
	[[ $output == *"mode=batch"* ]]
	[[ $output == *'printf "%s" "$cmds" | kgdb -q "$debug" "vmcore.$n"'* ]]
	[[ $output == *'zstd -q -d -o "vmcore.$n" "vmcore.$n.zst"'* ]]
	run "$FBSD" -n crash x
	[ "$status" -eq 2 ]
}

@test "check: metadata rules match the project's checklist workflow" {
	command -v git >/dev/null || skip "git not installed"
	repo=$T/src
	mkdir -p "$repo/tools/build" "$repo/.github"
	printf '#!/bin/sh\necho "style ok"\n' >"$repo/tools/build/checkstyle9.pl"
	chmod +x "$repo/tools/build/checkstyle9.pl"
	printf 'contrib\t:warning: vendor branch\n' >"$repo/.github/path-rules.txt"
	printf '/contrib/foo @someone\n' >"$repo/.github/CODEOWNERS"
	g() { git -C "$repo" -c user.name=T -c user.email=t@example.org "$@"; }
	g init -q -b main
	g add -A && g commit -q -m base
	g branch -q base
	mkdir -p "$repo/contrib/foo"
	echo a >"$repo/contrib/foo/a.c" && g add -A && g commit -q -m "no sob"
	echo b >"$repo/b.c" && g add -A && g commit -q -m $'bad case\n\nsigned-off-by: T <t@example.org>'
	echo c >"$repo/c.c" && g add -A && g commit -q -m $'good\n\nSigned-off-by: T <t@example.org>'
	echo d >"$repo/d.c" && g add -A && g -c user.email=x@users.noreply.github.com commit -q -m $'noreply\n\nSigned-off-by: X <x@users.noreply.github.com>'
	script=$(FBSD_SRC=$repo "$FBSD" -n check -r base..HEAD | sed -n '/^# ---- guest script/,/^# ---- end/p' | sed '1d;$d')
	run sh -c "$script"
	[ "$status" -eq 1 ]
	[[ $output == *"style ok"* ]]
	[[ $output == *": missing Signed-off-by line"* ]]
	[[ $output == *': expected exactly "Signed-off-by: "'* ]]
	[[ $output == *": a real email address is needed"* ]]
	[[ $output == *"contrib: :warning: vendor branch"* ]]
	[[ $output == *"contrib/foo: review wanted from @someone"* ]]
	[ "$(grep -c 'missing Signed-off-by' <<<"$output")" -eq 1 ]
}

@test "check -n: default range and range validation" {
	run "$FBSD" -n check
	[[ $output == *"range=origin/main..HEAD"* ]]
	run "$FBSD" -n check -r 'a;b'
	[ "$status" -eq 2 ]
}

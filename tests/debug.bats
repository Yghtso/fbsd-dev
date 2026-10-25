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
	[[ $output == *"keep=0"* && $output == *'trap "rm -f /var/crash/$tmpcore'* ]]
	run "$FBSD" -n crash -K
	[[ $output == *"keep=1"* ]]
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
	[[ $output == *"WARNING: .github/workflows/checklist.yml differs"*"the sh rules may be stale"* ]]
	[[ $output == *"note: .github/path-rules.txt changed since"* ]]
}

@test "check -n: default range and range validation" {
	run "$FBSD" -n check
	[[ $output == *"range=origin/main..HEAD"* ]]
	run "$FBSD" -n check -r 'a;b'
	[ "$status" -eq 2 ]
}

@test "kmod -n: user build against the kernel build dir, root kld ops" {
	run "$FBSD" -n kmod nullfs
	[ "$status" -eq 0 ]
	[[ $output == *"dir=sys/modules/nullfs"* ]]
	[[ $output == *'kbd=$obj$src/$(uname -m).$(uname -p)/sys/$kernconf'* ]]
	[[ $output == *'$su kldunload $force "$kmod"'* ]]
	[[ $output == *'$su kldload "$ko"'* ]]
	[[ $output == *"show_dmesg"* ]]
	run "$FBSD" -n kmod -F sys/modules/if_vtnet
	[[ $output == *"force=-f"* && $output == *"dir=sys/modules/if_vtnet"* ]]
	run "$FBSD" -n kmod ../x
	[ "$status" -eq 2 ]
	run "$FBSD" -n kmod a b
	[ "$status" -eq 2 ]
}

@test "pr -n: refuses main, rebases, never pushes" {
	run "$FBSD" -n pr
	[ "$status" -eq 0 ]
	[[ $output == *'main | stable/* | releng/*)'* ]]
	[[ $output == *"git fetch origin"* ]]
	[[ $output == *"git rebase origin/main"* ]]
	[[ $output == *"fbsd check -r origin/main..HEAD"* ]]
	[ "$(printf '%s\n' "$output" | grep -v '^#' | grep -v 'echo ' | grep -c 'git push')" -eq 0 ]
}

@test "pr: push command printed, with --force-with-lease when needed" {
	grep -q 'push$lease -u $fork $branch' "$BATS_TEST_DIRNAME/../libexec/fbsd/fbsd-pr"
	grep -q "lease=' --force-with-lease'" "$BATS_TEST_DIRNAME/../libexec/fbsd/fbsd-pr"
}

@test "compdb -n: clangd matching base clang, meta files, clangd --check" {
	run "$FBSD" -n compdb
	[ "$status" -eq 0 ]
	[[ $output == *'clangd=/usr/local/bin/clangd$major'* ]]
	[[ $output == *'$su pkg install -y "llvm$major"'* ]]
	[[ $output == *'-path "$top/tmp" -prune'* ]]
	[[ $output == *'find "$top/obj-lib32" -name "*.meta"'* ]]
	[[ $output == *'grep -vc "tweak: "'* ]]
	[[ $output == *'out=$src/compile_commands.json'* ]]
	[[ $output == *"checks='sys/kern/kern_shutdown.c lib/libc/stdlib/qsort.c'"* ]]
	[[ $output == *'--check="$src/$f"'* ]]
	run "$FBSD" -n compdb -c sys/dev/foo.c
	[[ $output == *"checks=sys/dev/foo.c"* ]]
	run "$FBSD" -n compdb -c /etc/passwd
	[ "$status" -eq 2 ]
}

@test "compdb: the awk generator turns .meta files into valid JSON" {
	command -v jq >/dev/null || skip "jq not installed"
	d=$T/obj
	mkdir -p "$d"
	printf 'CMD cc -c -O2 -I. /usr/src/sys/kern/a.c\nCMD ctfconvert a.o\nCWD /obj/sys/GENERIC\nTARGET a.o\n' >"$d/a.o.meta"
	printf 'CMD cc -DX=\\"y\\" -c b.c -o b.o\nCWD /obj/lib\n' >"$d/b.o.meta"
	printf 'CMD cc -c b.c -o b.pico -fPIC\nCWD /obj/lib\n' >"$d/b.pico.meta"
	printf 'CMD ln -s x y\nCWD /obj\n' >"$d/c.meta"
	awkprog=$("$FBSD" -n compdb | sed -n '/^cat >"\$awkf" <<"AWK"$/,/^AWK$/p' | sed '1d;$d')
	out=$(printf '%s\n' "$d"/*.meta | awk "$awkprog" 2>"$T/n")
	[ "$(cat "$T/n")" -eq 2 ]
	[ "$(printf '%s' "$out" | jq length)" -eq 2 ]
	[ "$(printf '%s' "$out" | jq -r '.[0].file')" = /usr/src/sys/kern/a.c ]
	[ "$(printf '%s' "$out" | jq -r '.[1].file')" = /obj/lib/b.c ]
	[ "$(printf '%s' "$out" | jq -r '.[1].command')" = 'cc -DX=\"y\" -c b.c -o b.o' ]
}

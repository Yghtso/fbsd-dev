# fbsd

Personal toolkit for developing FreeBSD-CURRENT in a persistent QEMU/KVM
guest from an Arch Linux host. Thin POSIX sh wrappers around qemu, ssh,
make, nextboot, bectl, kyua, gdb and git. Every command takes `-h`; `-n`
prints what it would do (guest scripts as plain text), `-nn` the exact
host command lines.

## Setup (once)

```sh
ln -s "$PWD/bin/fbsd" ~/.local/bin/fbsd
cp etc/fbsd.conf.example ~/.config/fbsd/fbsd.conf   # optional, every key has a default
fbsd doctor                                         # host and guest checks, with fixes
```

A new VM: `fbsd vm create` (official CURRENT cloud-init image), then
`fbsd vm prep` (sudo, sshd, ARC, panic/dump settings, ntpd, /usr/src clone).

## Daily workflow

Sources live in the guest (`/usr/src`, owned by you); edit them there
(`fbsd ssh`, then Neovim; `fbsd compdb` gives clangd its database).

```sh
fbsd vm up -w                      # boot, wait for sshd
fbsd ssh                           # edit in the guest; git switch -c my-fix

fbsd build kernel                  # unprivileged; log on the host, UPDATING news
fbsd ktest                         # /boot/kernel.test, one boot via nextboot;
                                   # a panic falls back to /boot/kernel
fbsd ktest --ddb                   # same, but stop in ddb on panic
fbsd kmod <module>                 # module only: rebuild + kldunload + kldload

fbsd test -i <srcdir> <path>       # install that tests dir, run kyua on /usr/tests

fbsd check                         # style(9), Signed-off-by, mandoc on your commits
fbsd pr                            # fetch, rebase on origin/main, check, print the push command
```

Userland changes: `fbsd build world`, then `fbsd install world -r` (new
boot environment via beinstall.sh, booted once; keep it with
`fbsd ssh sudo bectl activate <name>`).

## When something breaks

```sh
fbsd vm log -t 60                  # serial console log (boots, panics)
fbsd vm console                    # attach to the serial console (Ctrl-] detaches)
fbsd crash -l                      # dumps saved by savecore; -s summary; -c bt
fbsd gdb                           # host gdb on the QEMU gdbstub (stops the guest)
fbsd build -a                      # reattach to a build after a disconnect
fbsd vm snap save <name>           # qcow2 snapshot (VM off); revert -f, delete -f
fbsd vm down -f                    # pull the plug on a hung VM
```

Safety nets, in order: `nextboot` (test kernels) → boot environments
(`default` is the pkgbase rescue BE) → qcow2 snapshots.

## Development

```sh
shellcheck -s sh bin/fbsd libexec/fbsd/* lib/fbsd/*.sh tests/stubs/*
shellcheck -x tests/*.bats tests/helper.bash
bats tests/
```

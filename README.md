# fbsd

Personal toolkit for developing FreeBSD-CURRENT in a persistent QEMU/KVM
guest from an Arch Linux host. Thin POSIX sh wrappers around qemu, ssh,
make, kyua, bectl and friends. Every command takes `-n` (print the exact
commands, change nothing) and `-h`.

## Setup

    ln -s "$PWD/bin/fbsd" ~/.local/bin/fbsd
    mkdir -p ~/.config/fbsd
    cp etc/fbsd.conf.example ~/.config/fbsd/fbsd.conf   # optional, all keys have defaults
    fbsd doctor

## Daily use

    fbsd vm up -w          # boot, wait for sshd
    fbsd ssh               # shell in the guest (ControlMaster, instant reconnects)
    fbsd vm console        # serial console, Ctrl-] detaches
    fbsd vm log -t 50      # last lines of the console log (boots, panics)
    fbsd vm down           # ACPI shutdown; -f to pull the plug
    fbsd -n vm up          # show the qemu command line

## Development

    shellcheck -s sh bin/fbsd libexec/fbsd/* lib/fbsd/*.sh tests/stubs/*
    shellcheck -x tests/*.bats tests/helper.bash
    bats tests/

#!/usr/bin/env bash
# shellcheck disable=SC2088,SC2016  # ~ and $ in quoted vm commands expand on the vm, on purpose
# test-vm.sh — prove setup.sh on a throwaway arch vm (official arch-boxes image)
#
#   setup/test-vm.sh [hostname]      default "testbox" = the default profile
#
# mimics archinstall (networkmanager, user friend), copies this checkout in, runs
# setup.sh twice — the second run must change nothing — then setup.sh check.
# vm disk lives in ~/.cache/setup-vm and is thrown away; the base image is kept.
set -euo pipefail

CONF=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
DIR=${XDG_CACHE_HOME:-$HOME/.cache}/setup-vm
BASE=https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-basic.qcow2
IMG=$DIR/arch-basic.qcow2
DISK=$DIR/run.qcow2
PORT=2299
NAME=${1:-testbox}
TUSER=friend  # not the author: proves nothing is tied to one person
SSHO=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -p "$PORT")

say() { printf '\n== %s\n' "$*"; }
fail() { printf 'test-vm: FAIL — %s\n' "$*" >&2; exit 1; }
vm() { ssh "${SSHO[@]}" -i "$DIR/key" "$TUSER@127.0.0.1" "$@"; }
vm_arch() { sshpass -p arch ssh "${SSHO[@]}" arch@127.0.0.1 "$@"; }
wait_ssh() { # user
  for _ in $(seq 90); do
    if [[ $1 == arch ]]; then vm_arch true 2>/dev/null && return; else vm true 2>/dev/null && return; fi
    sleep 2
  done
  fail "vm never answered ssh"
}
boot() {
  HEAVY_MEM=6G heavy qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4096 \
    -drive "file=$DISK,if=virtio" -nic "user,model=virtio,hostfwd=tcp:127.0.0.1:$PORT-:22" \
    -display none -daemonize -pidfile "$DIR/qemu.pid"
}
stop() { [[ -f $DIR/qemu.pid ]] && kill "$(<"$DIR/qemu.pid")" 2>/dev/null; rm -f "$DIR/qemu.pid"; return 0; }

command -v sshpass qemu-system-x86_64 >/dev/null || fail "needs sshpass + qemu"
mkdir -p "$DIR"
trap 'stop; rm -f "$DISK"' EXIT

say "image"
if [[ ! -f $IMG ]]; then
  curl -fL --progress-bar -o "$IMG.part" "$BASE"
  want=$(curl -fsS "$BASE.SHA256" | awk '{print $1}')
  [[ $(sha256sum "$IMG.part" | awk '{print $1}') == "$want" ]] || fail "image checksum mismatch"
  mv "$IMG.part" "$IMG"
fi
[[ -f $DIR/key ]] || ssh-keygen -q -t ed25519 -N '' -f "$DIR/key"
qemu-img create -q -f qcow2 -F qcow2 -b "$IMG" "$DISK"

say "boot + make it look like archinstall (networkmanager, user $TUSER, hostname $NAME)"
boot
wait_ssh arch
vm_arch 'sudo -n sh -s' <<EOF
set -e
useradd -m -G wheel $TUSER
echo "$TUSER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-test-vm
install -d -m 700 -o $TUSER -g $TUSER /home/$TUSER/.ssh
echo '$(<"$DIR/key.pub")' > /home/$TUSER/.ssh/authorized_keys
chown $TUSER:$TUSER /home/$TUSER/.ssh/authorized_keys
hostnamectl set-hostname $NAME
pacman -Sy --noconfirm --needed archlinux-keyring >/dev/null
pacman -Su --noconfirm --needed networkmanager git >/dev/null
systemctl disable systemd-networkd systemd-networkd.socket 2>/dev/null || true
systemctl enable NetworkManager
EOF
vm_arch 'sudo -n systemctl reboot' || true
sleep 5
wait_ssh user

say "copy this checkout to ~/sync/config"
(cd "$CONF" && { git ls-files -co --exclude-standard -- . ':!claude'; git ls-files -c -- claude; } \
  | tar -cf - -T -) | vm 'mkdir -p ~/sync/config && tar -xf - -C ~/sync/config'

say "run 1"
vm '~/sync/config/setup.sh' || fail "first run failed"

say "run 2 (must change nothing)"
out=$(vm '~/sync/config/setup.sh' 2>&1) || { echo "$out"; fail "second run failed"; }
echo "$out" | grep -E '^  (done|warn)' || true
changed=$(echo "$out" | grep -c '^  done' || true)
((changed == 0)) || fail "second run changed $changed thing(s) — not idempotent"

say "check"
vm '~/sync/config/setup.sh check' || true

say "smoke"
vm 'for c in dwl foot claude paru ~/.local/bin/sync-bin/wm; do command -v $c >/dev/null && echo "  ok $c" || echo "  MISSING $c"; done' | tee "$DIR/smoke"
grep -q MISSING "$DIR/smoke" && fail "missing commands"
say "PASS"

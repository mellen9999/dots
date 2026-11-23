#!/usr/bin/env bash
# shellcheck disable=SC2088,SC2016  # $ in quoted vm commands expands on the vm, on purpose
# test-install.sh — prove install.sh the way a friend runs it, on a throwaway uefi vm:
# boots the real arch iso, answers the questions, reboots into the new system,
# types the disk password, checks the result, then logs in so the first-login
# hook runs setup.sh.
#
#   setup/test-install.sh          everything (~45 min)
#   setup/test-install.sh quick    stop after the install checks (~10 min)
#
# tests what's committed on this checkout's branch (served to the vm as a git repo).
set -euo pipefail

CONF=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
DIR=${XDG_CACHE_HOME:-$HOME/.cache}/setup-vm
ISO=$DIR/archlinux.iso
ISO_URL=https://geo.mirror.pkgbuild.com/iso/latest
OVMF=/usr/share/edk2/x64
W=$DIR/install
PORT=2298 HTTP=8098
TUSER=friend PW=test1pass ZONE=America/Chicago
MODE=${1:-full}
SSHO=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -i "$DIR/key" -p "$PORT")

say() { printf '\n== %s\n' "$*"; }
fail() { printf 'test-install: FAIL — %s\n' "$*" >&2; exit 1; }
as() { local u=$1; shift; ssh "${SSHO[@]}" "$u@127.0.0.1" "$@"; }
wait_ssh() { # user tries
  for _ in $(seq "$2"); do as "$1" true 2>/dev/null && return; sleep 2; done
  return 1
}
qemu() {
  HEAVY_MEM=6G heavy qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 4 -m 4096 \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF/OVMF_CODE.4m.fd" \
    -drive "if=pflash,format=raw,file=$W/vars.fd" \
    -drive "file=$W/disk.qcow2,if=virtio" \
    -nic "user,model=virtio,hostfwd=tcp:127.0.0.1:$PORT-:22" \
    -monitor "unix:$W/mon,server,nowait" -display none -daemonize -pidfile "$W/qemu.pid" "$@"
}
stop() {
  [[ -f $W/qemu.pid ]] || return 0
  local p; p=$(<"$W/qemu.pid")
  kill "$p" 2>/dev/null || true
  while kill -0 "$p" 2>/dev/null; do sleep 1; done
  rm -f "$W/qemu.pid"
}
type_line() { # sendkey can only do lowercase letters + digits here, which is all PW uses
  local i
  for ((i = 0; i < ${#1}; i++)); do echo "sendkey ${1:i:1}" | socat - "UNIX-CONNECT:$W/mon" >/dev/null; done
  echo 'sendkey ret' | socat - "UNIX-CONNECT:$W/mon" >/dev/null
}
cleanup() { stop; [[ -n ${WEB:-} ]] && kill "$WEB" 2>/dev/null; rm -rf "$W"; }

command -v qemu-system-x86_64 bsdtar socat python3 >/dev/null || fail "needs qemu, libarchive (bsdtar), socat, python"
[[ $PW =~ ^[a-z0-9]+$ ]] || fail "PW must be lowercase letters + digits (sendkey)"
mkdir -p "$DIR"
trap cleanup EXIT
cleanup
mkdir -p "$W/www"

say "iso"
want=$(curl -fsS "$ISO_URL/sha256sums.txt" | awk '$2 == "archlinux-x86_64.iso" {print $1}')
if [[ ! -f $ISO || $(sha256sum "$ISO" | awk '{print $1}') != "$want" ]]; then
  curl -fL --progress-bar -o "$ISO.part" "$ISO_URL/archlinux-x86_64.iso"
  [[ $(sha256sum "$ISO.part" | awk '{print $1}') == "$want" ]] || fail "iso checksum mismatch"
  mv "$ISO.part" "$ISO"
fi
bsdtar -xf "$ISO" -C "$W" arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img loader/entries/01-archiso-linux.conf
opts=$(awk '$1 == "options" {$1 = ""; print}' "$W/loader/entries/01-archiso-linux.conf")
[[ -f $DIR/key ]] || ssh-keygen -q -t ed25519 -N '' -f "$DIR/key"

say "serve this branch + an ssh key to the vm"
git clone -q --bare "$CONF" "$W/www/dots.git"
git -C "$W/www/dots.git" update-server-info
printf 'install -d -m 700 /root/.ssh\necho %q >/root/.ssh/authorized_keys\nsystemctl start sshd\n' \
  "$(<"$DIR/key.pub")" >"$W/www/boot.sh"
python3 -m http.server -b 127.0.0.1 -d "$W/www" "$HTTP" >/dev/null 2>&1 &
WEB=$!

say "boot the iso"
cp "$OVMF/OVMF_VARS.4m.fd" "$W/vars.fd"
qemu-img create -q -f qcow2 "$W/disk.qcow2" 40G
qemu -cdrom "$ISO" -kernel "$W/arch/boot/x86_64/vmlinuz-linux" -initrd "$W/arch/boot/x86_64/initramfs-linux.img" \
  -append "$opts script=http://10.0.2.2:$HTTP/boot.sh"
wait_ssh root 120 || fail "iso never answered ssh"

say "install.sh (disk 1, $TUSER, chicago)"
as root 'cat >/root/install.sh' <"$CONF/install.sh"
printf '1\n%s\n%s\n%s\nchicago\nerase\n' "$TUSER" "$PW" "$PW" |
  as root "DOTS=http://10.0.2.2:$HTTP/dots.git bash /root/install.sh" || fail "install.sh failed"

say "test-only: ssh into the new system"
as root sh -s <<EOF
set -e
printf '%s' '$PW' | cryptsetup open --key-file=- /dev/vda2 root
mount -o subvol=@ /dev/mapper/root /mnt
mount -o subvol=@home /dev/mapper/root /mnt/home
mount -o subvol=@log /dev/mapper/root /mnt/var/log
mount -o subvol=@pkg /dev/mapper/root /mnt/var/cache/pacman/pkg
arch-chroot /mnt pacman -S --noconfirm --needed openssh >/dev/null
arch-chroot /mnt systemctl enable -q sshd
install -d -m 700 /mnt/home/$TUSER/.ssh
cp /root/.ssh/authorized_keys /mnt/home/$TUSER/.ssh/
arch-chroot /mnt chown -R $TUSER: /home/$TUSER/.ssh
umount -R /mnt
cryptsetup close root
EOF
as root poweroff || true
while [[ -f $W/qemu.pid ]] && kill -0 "$(<"$W/qemu.pid")" 2>/dev/null; do sleep 1; done
rm -f "$W/qemu.pid"

say "boot the new system + type the disk password"
qemu
up=0
for _ in 1 2 3; do
  sleep 25
  type_line "$PW"
  wait_ssh "$TUSER" 45 && { up=1; break; }
done
((up)) || fail "new system never came up (screen: echo 'screendump x.ppm' | socat - UNIX-CONNECT:$W/mon)"

say "checks"
as "$TUSER" PW="$PW" ZONE="$ZONE" bash -s <<'EOF'
s() { printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
c() { if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; else echo "  FAIL $1"; bad=1; fi; }
bad=0
c "root is btrfs subvol @"        '[[ $(findmnt -no FSTYPE,OPTIONS /) == btrfs*subvol=/@* ]]'
c "disk is encrypted"             'lsblk -no TYPE | grep -qx crypt'
c "both kernels boot images"      's test -s /boot/EFI/Linux/arch-linux.efi && s test -s /boot/EFI/Linux/arch-linux-lts.efi'
c "booted the default kernel"     '[[ $(uname -r) != *lts* ]]'
c "snapshots configured"          's snapper list-configs | grep -q "^root"'
c "timezone $ZONE"                '[[ $(timedatectl show -p Timezone --value) == "$ZONE" ]]'
c "sudo works"                    's true'
c "root login locked"             's passwd -S root | grep -q " L "'
c "online via networkmanager"     'systemctl is-active -q NetworkManager && curl -fsS -o /dev/null https://archlinux.org'
c "dots cloned"                   'git -C ~/sync/config rev-parse HEAD'
c "first-login hook armed"        'test -e ~/.setup-pending && grep -q setup.sh ~/.bash_profile'
c "no failed units"               '[[ -z $(systemctl --failed --no-legend) ]]'
exit $bad
EOF
[[ $MODE == quick ]] && { say "PASS (quick)"; exit 0; }

say "first login (runs setup.sh, 20-40 min)"
# test-only: no sudo prompts (a NOPASSWD rule alone still prompts sudo -v while %wheel also matches)
as "$TUSER" "printf '%s\n' '$PW' | sudo -S -p '' sh -c 'echo \"Defaults:$TUSER !authenticate\" >/etc/sudoers.d/90-test'"
printf 'exit\n' | timeout 3600 ssh -tt "${SSHO[@]}" "$TUSER@127.0.0.1" || true
as "$TUSER" '! test -e ~/.setup-pending' || fail "first login didn't finish (hook still armed)"

say "setup.sh again (must change nothing)"
out=$(as "$TUSER" '~/sync/config/setup.sh' 2>&1) || { echo "$out"; fail "second run failed"; }
changed=$(grep -c '^  done' <<<"$out" || true)
((changed == 0)) || { grep '^  done' <<<"$out"; fail "second run changed $changed thing(s)"; }

say "after setup"
as "$TUSER" '~/sync/config/setup.sh check' || fail "setup.sh check found drift"
as "$TUSER" 'bash -lic "command -v wm" &>/dev/null && echo "  ok wm on login path" && for c in dwl foot paru snapper claude firefox; do command -v $c >/dev/null && echo "  ok $c" || { echo "  MISSING $c"; exit 1; }; done' ||
  fail "missing commands"
say "PASS"

#!/usr/bin/env bash
# install.sh — put arch on a computer, ready for setup.sh. run it from the arch usb:
#
#   curl -LO https://raw.githubusercontent.com/mellen9999/dots/main/install.sh
#   bash install.sh
#
# asks for a disk, your name, a password and your city, shows what it will do,
# and wipes nothing until you type "erase". you get: encrypted disk (luks2),
# btrfs with snapshots, systemd-boot with two kernels (linux + linux-lts as a
# spare), networkmanager (carries over the usb's wifi), and this repo in
# ~/sync/config. the first login runs setup.sh by itself.
set -Eeuo pipefail

DOTS=${DOTS:-https://github.com/mellen9999/dots}
PKGS=(base linux linux-lts linux-firmware amd-ucode intel-ucode sof-firmware
  btrfs-progs cryptsetup dosfstools mkinitcpio networkmanager sudo git snapper)

if [[ -t 1 ]]; then B=$'\e[1m' R=$'\e[31m' G=$'\e[32m' N=$'\e[0m'; else B='' R='' G='' N=''; fi
say() { printf '\n%s== %s%s\n' "$B" "$*" "$N"; }
die() { printf '\n%sinstall: %s%s\n' "$R" "$*" "$N" >&2; cleanup 2>/dev/null; exit 1; }
desc() { lsblk -dno SIZE,MODEL "$1" | sed -E 's/^ +| +$//g; s/ +/ /g'; }
ask() { printf '%s' "$1" >&2; read -r REPLY || die "no answer — stopped"; }

cleanup() {
  mountpoint -q /mnt && umount -R /mnt
  [[ -e /dev/mapper/root ]] && cryptsetup close root
  return 0
}
trap 'printf "\n%sinstall: stopped at line %s (%s)%s\nfix that (usually the internet) and run it again:  bash install.sh\n" "$R" "$LINENO" "$BASH_COMMAND" "$N" >&2; cleanup 2>/dev/null' ERR
trap 'die cancelled' INT

# --- checks ------------------------------------------------------------------

((EUID == 0)) || die "run it as root (the arch usb already is)"
[[ -d /run/archiso ]] || die "run it from the arch usb, not from an installed system"
[[ -d /sys/firmware/efi ]] || die "the usb started in old bios mode. restart, open the boot menu, and pick the usb entry that says UEFI"
curl -fsS --max-time 15 -o /dev/null https://archlinux.org ||
  die "no internet. plug in a cable or phone (usb tethering), or wifi:  iwctl station wlan0 connect \"your wifi name\""
cleanup

# --- questions (nothing is touched until the very end) -----------------------

say "which disk? everything on it gets erased"
usb=$(lsblk -no PKNAME "$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null)" 2>/dev/null || true)
disks=()
while read -r name type bytes; do
  [[ $type == disk && $name != /dev/zram* && ${name#/dev/} != "$usb" ]] || continue
  ((bytes >= 20 * 1024 ** 3)) || continue
  disks+=("$name")
  printf '  %d) %s  %s\n' "${#disks[@]}" "$name" "$(desc "$name")"
done < <(lsblk -dnpbo NAME,TYPE,SIZE)
((${#disks[@]})) || die "no disk of 20G or more found"
while :; do
  ask "number [1]: "; n=${REPLY:-1}
  [[ $n =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#disks[@]})) && break
done
disk=${disks[n - 1]}

say "your name (for logging in: lowercase, no spaces)"
while :; do
  ask "name: "; user=$REPLY
  [[ $user =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || { echo "  lowercase letters and numbers only, like: alex"; continue; }
  getent passwd "$user" >/dev/null && { echo "  that one's taken by the system, pick another"; continue; }
  break
done

say "password — unlocks the disk at power on and logs you in. don't lose it: no reset"
while :; do
  printf 'password: ' >&2; read -rs pw || die "no answer — stopped"; echo >&2
  printf 'again: ' >&2; read -rs pw2 || die "no answer — stopped"; echo >&2
  [[ -n $pw && $pw == "$pw2" ]] && break
  echo "  empty or didn't match, again"
done
unset pw2

say "your city (sets the clock)"
mapfile -t zones < <(timedatectl list-timezones)
while :; do
  ask "city, like chicago, london, tokyo: "; q=${REPLY,,}; q=${q// /_}
  [[ -n $q ]] || continue
  hits=()
  for z in "${zones[@]}"; do l=${z,,}; [[ $l == "$q" || ${l##*/} == "$q" ]] && hits+=("$z"); done
  ((${#hits[@]})) || for z in "${zones[@]}"; do l=${z,,}; [[ ${l##*/} == *"$q"* ]] && hits+=("$z"); done
  if ((${#hits[@]} == 1)); then zone=${hits[0]}; break; fi
  if ((${#hits[@]} == 0 || ${#hits[@]} > 9)); then echo "  not found — try the biggest city near you in the same time zone"; continue; fi
  for i in "${!hits[@]}"; do printf '  %d) %s\n' $((i + 1)) "${hits[i]}"; done
  ask "number: "
  [[ $REPLY =~ ^[0-9]+$ ]] && ((REPLY >= 1 && REPLY <= ${#hits[@]})) && { zone=${hits[REPLY - 1]}; break; }
done

say "ready"
printf '  disk   %s  %s  %s<- ERASED%s\n' "$disk" "$(desc "$disk")" "$R" "$N"
printf '  name   %s\n  clock  %s\n' "$user" "$zone"
ask "type erase to wipe that disk and install, anything else quits: "
[[ $REPLY == erase ]] || die "nothing changed"

# --- disk: 1G boot partition + the rest encrypted, btrfs inside --------------

say "disk"
wipefs -aq "$disk"
sgdisk -Z "$disk" >/dev/null
sgdisk -n1:0:+1G -t1:ef00 -c1:boot -n2:0:0 -t2:8309 -c2:root "$disk" >/dev/null
partprobe "$disk" 2>/dev/null || true
udevadm settle
mapfile -t parts < <(lsblk -lnpo NAME,TYPE "$disk" | awk '$2 == "part" {print $1}')
((${#parts[@]} == 2)) || die "expected 2 partitions on $disk, found ${#parts[@]}"
esp=${parts[0]} crypt=${parts[1]}
wipefs -aq "$esp" "$crypt"

printf '%s' "$pw" | cryptsetup -q luksFormat --type luks2 --key-file=- "$crypt"
printf '%s' "$pw" | cryptsetup open --key-file=- "$crypt" root
mkfs.fat -F32 -n BOOT "$esp" >/dev/null
mkfs.btrfs -qf -L arch /dev/mapper/root

mount /dev/mapper/root /mnt
for s in @ @home @log @pkg; do btrfs subvolume create "/mnt/$s" >/dev/null; done
umount /mnt
o=noatime,compress=zstd
mount -o "$o,subvol=@" /dev/mapper/root /mnt
mount --mkdir -o "$o,subvol=@home" /dev/mapper/root /mnt/home
mount --mkdir -o "$o,subvol=@log" /dev/mapper/root /mnt/var/log
mount --mkdir -o "$o,subvol=@pkg" /dev/mapper/root /mnt/var/cache/pacman/pkg
mount --mkdir -o fmask=0077,dmask=0077 "$esp" /mnt/boot

# boot config goes in before the kernels, so their one initramfs build makes the final images
install -d /mnt/etc/kernel /mnt/etc/mkinitcpio.conf.d /mnt/etc/mkinitcpio.d /mnt/boot/EFI/Linux
echo "rd.luks.name=$(blkid -s UUID -o value "$crypt")=root root=/dev/mapper/root rootflags=subvol=@ rw quiet zswap.enabled=0" \
  >/mnt/etc/kernel/cmdline
# keyboard before autodetect: a keyboard plugged in later can still type the disk password
echo 'HOOKS=(base systemd keyboard autodetect microcode modconf kms sd-vconsole block sd-encrypt filesystems fsck)' \
  >/mnt/etc/mkinitcpio.conf.d/hooks.conf
echo KEYMAP=us >/mnt/etc/vconsole.conf
for k in linux linux-lts; do
  printf 'ALL_kver="/boot/vmlinuz-%s"\nPRESETS=(default)\ndefault_uki="/boot/EFI/Linux/arch-%s.efi"\n' "$k" "$k" \
    >"/mnt/etc/mkinitcpio.d/$k.preset"
done

# --- system ------------------------------------------------------------------

say "downloading + installing (5-15 min)"
pacman -Sy --needed --noconfirm archlinux-keyring >/dev/null
pacstrap -K /mnt "${PKGS[@]}"
genfstab -U /mnt | sed -E 's/,subvolid=[0-9]+//' >>/mnt/etc/fstab
for k in linux linux-lts; do [[ -s /mnt/boot/EFI/Linux/arch-$k.efi ]] || die "boot image for $k wasn't built"; done

say "settings"
arch-chroot /mnt /bin/bash -e <<EOF
ln -sf /usr/share/zoneinfo/$zone /etc/localtime
hwclock --systohc 2>/dev/null || true  # no rtc on some boards; ntp sets the time anyway
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen >/dev/null
echo LANG=en_US.UTF-8 >/etc/locale.conf
echo arch >/etc/hostname
useradd -m -G wheel -s /bin/bash $user
passwd -l root >/dev/null
echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
bootctl install --graceful >/dev/null 2>&1  # graceful: some firmware refuses boot entries; the fallback path still boots
test -s /boot/EFI/BOOT/BOOTX64.EFI
printf 'default arch-linux.efi\ntimeout 3\neditor no\n' >/boot/loader/loader.conf
systemctl enable -q NetworkManager systemd-timesyncd systemd-boot-update
snapper --no-dbus -c root create-config /
EOF
printf '%s:%s' "$user" "$pw" | arch-chroot /mnt chpasswd
unset pw

# wifi the usb is connected to → networkmanager, so the first boot is online
i=0
for f in /var/lib/iwd/*.psk; do
  [[ -f $f ]] || continue
  ssid=${f##*/}; ssid=${ssid%.psk}
  [[ $ssid == =* ]] && ssid=$(printf '%b' "$(sed 's/../\\x&/g' <<<"${ssid#=}")")
  key=$(sed -n 's/^Passphrase=//p' "$f"); [[ -n $key ]] || key=$(sed -n 's/^PreSharedKey=//p' "$f")
  [[ -n $key ]] || continue
  i=$((i + 1))
  install -m 600 /dev/stdin "/mnt/etc/NetworkManager/system-connections/wifi-$i.nmconnection" <<EOF
[connection]
id=$ssid
type=wifi

[wifi]
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$key
EOF
done

say "dotfiles"
home=/home/$user
arch-chroot -u "$user" /mnt env HOME="$home" git clone -q "$DOTS" "$home/sync/config"
cat >"/mnt$home/.bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc

# first login finishes the setup (safe to stop and log in again: it picks up where it was)
if [[ -e ~/.setup-pending && -t 0 ]] && ~/sync/config/setup.sh; then rm ~/.setup-pending; exec bash -l; fi

# logging in on the main screen starts the desktop
[[ $(tty) == /dev/tty1 && -z ${WAYLAND_DISPLAY:-} && ! -e ~/.setup-pending ]] && command -v wm >/dev/null && exec wm
EOF
touch "/mnt$home/.setup-pending"
arch-chroot /mnt chown "$user:$user" "$home/.bash_profile" "$home/.setup-pending"

sync
cleanup
say "${G}installed$N"
cat <<EOF
  1. type  poweroff  and take out the usb, then turn it back on
  2. type your password to unlock the disk (nothing shows while typing)
  3. log in as $user with the same password
  4. setup finishes by itself (20-40 min), then the desktop starts
EOF

# new box

fresh arch → this setup. two parts: archinstall (disks, boot), then `setup.sh` (everything else).

## 1. archinstall

boot the arch usb, run `archinstall`, pick:

- disk: wipe it, **btrfs** with default subvolumes, compression on, snapper snapshots
- disk encryption: **luks**, set a passphrase
- bootloader: **systemd-boot**, unified kernel images **on**
- kernels: **linux** + **linux-lts**
- profile: **minimal**
- audio: **pipewire**
- network: **NetworkManager**
- user: your name, sudo **yes**
- hostname: anything — a matching `setup/hosts/<hostname>` adds that box's extras, otherwise you get the default

reboot into the new system, log in.

## 2. setup

```
sudo pacman -S --needed git
git clone https://github.com/mellen9999/dots ~/sync/config
~/sync/config/setup.sh
```

(a private fork with your own host profiles works the same: clone it to `~/sync/config` instead.)

it asks for your password once, then runs on its own (20–40 min, mostly downloads). it ends with a short list of things only you can do (git name/email, tailscale login, secure boot). safe to re-run any time — it only does what's missing.

your own extras (more packages, repos to clone, backups) go in `setup/hosts/<your-hostname>` — copy `hosts/heatlaptop` style: source `default`, then add.

## after

- `setup.sh check` — what's drifted from the lists (exit 1 if anything). changes nothing
- `setup.sh <step>` — one step: `pacman pkgs aur etc repos dots services handoff`
- new package → add it to a list in `setup/pkgs/`; new /etc file → `setup/etc.conf`; dotfile → `link.conf`
- what each box gets: `setup/hosts/<hostname>`

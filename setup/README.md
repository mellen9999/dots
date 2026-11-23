# install

a blank pc → arch linux + this setup. about an hour, mostly waiting.

you get: the dwl desktop, foot terminal, firefox, mpv, audio, a firewall, an encrypted disk with automatic snapshots, and a vim-flavored shell (tmux, vis, fzf, ripgrep). nothing else — add what you want with `sudo pacman -S <name>`.

you need:
- the pc. **its disk gets erased** — copy off anything you want to keep first
- a usb stick, 2gb or bigger (also gets erased)
- internet. a cable or your phone (usb tethering) is easiest; wifi works too
- graphics: amd or intel. nvidia isn't set up

## 1. make the usb

1. download `archlinux-x86_64.iso`: [archlinux.org/download](https://archlinux.org/download) → scroll to a mirror in your country → click it → the `.iso` file
2. put it on the stick:
   - windows: [rufus](https://rufus.ie) → pick the stick and the iso → start → if it asks, pick **dd image mode**
   - mac: [balena etcher](https://etcher.balena.io) → flash from file → the iso → the stick → flash
   - linux: `sudo dd if=archlinux-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync` (`lsblk` shows which sdX is the stick)

## 2. start from it

1. plug the stick in, turn the pc on, and keep tapping the boot menu key: usually **F12**, F11, F8 or Esc (it flashes on screen at power on)
2. pick the usb entry with **UEFI** in its name
3. pc boots normally instead, or says secure boot violation: open the bios settings (**Del** or **F2** at power on), turn **secure boot** off, save, try again
4. you're in when you see `root@archiso ~ #`. text tiny? type `setfont ter-132b`

## 3. internet

- cable or phone: nothing to do
- wifi: type `iwctl station wlan0 connect "your wifi name"`, then the wifi password
  ("no such device"? `iwctl device list` shows the real name to use instead of wlan0)
- check: `ping -c 3 archlinux.org` → lines with `time=` mean it works

## 4. install

type exactly:

```
curl -LO https://raw.githubusercontent.com/mellen9999/dots/main/install.sh
bash install.sh
```

it asks four things: which disk, your name, a password, your city. the password unlocks the disk and logs you in — **write it down, there's no reset**. nothing is erased until you type `erase`. then 10-20 min.

## 5. first start

1. type `poweroff`, pull the stick out, turn the pc on
2. type your password to unlock the disk (nothing shows while you type — normal)
3. log in: your name, same password
4. setup finishes by itself (20-40 min), then the desktop opens

from then on: password, log in, desktop. optional extras (secure boot, ssh key, …): `~/sync/config/setup.sh handoff` in a terminal lists what's left.

## using it

the windows key (super) runs everything:

| keys | does |
|---|---|
| super + shift + enter | terminal |
| super + p | open an app (type its name, enter) |
| super + j / k | next / previous window |
| super + 1 … 9 | switch workspace |
| super + shift + c | close a window |
| super + shift + q | leave the desktop |

all keys: `~/sync/config/dwl-config.h`

## stuck

- install stopped with a red line: fix what it says (usually the internet) and `bash install.sh` again
- setup stopped: `~/sync/config/setup.sh` again — it only does what's missing, safe any time
- what's out of date: `~/sync/config/setup.sh check`

## your own setup on top

- one step only: `setup.sh <step>` — `pacman pkgs aur etc repos dots services handoff`
- new package → a list in `setup/pkgs/`; /etc file → `setup/etc.conf`; dotfile → `link.conf`
- per-machine extras (packages, repos, backups) go in `setup/hosts/<hostname>`: source `default`, then add. rename the box with `sudo hostnamectl hostname <name>` and run `setup.sh`
- a private fork works the same: clone it to `~/sync/config` instead
- `setup/test-install.sh` runs all of this on a throwaway vm

# shellcheck shell=bash disable=SC2154  # profile arrays come from lib.sh
# copies etc.conf entries root-owned. existing files are backed up first; anything
# that can lock you out (sudoers, firewall, sshd) is validated before it goes live

ETC_BACKUP=/etc/.setup-backup/$TS

# files are per-user templates: @USER@ @UID@ @HOME@ become whoever runs setup
etc_render() { # src → path of the rendered copy
  local out
  out=$(mktemp "${TMPDIR:-/tmp}/setup-etc.XXXXXX")
  sed -e "s|@USER@|$USER|g" -e "s|@UID@|$(id -u)|g" -e "s|@HOME@|$HOME|g" "$CONF/$1" >"$out"
  echo "$out"
}

etc_same() { # dest src mode
  sudo test -f "$1" && sudo cmp -s "$2" "$1" && [[ $(sudo stat -c %a "$1") == "$3" ]]
}

etc_validate() { # dest src
  case $1 in
    /etc/sudoers.d/*) visudo -cqf "$2" ;;
    /etc/nftables.conf) sudo nft -c -f "$2" ;;
    *) return 0 ;;
  esac
}

etc_restore() { # dest
  if sudo test -e "$ETC_BACKUP$1"; then sudo cp -a "$ETC_BACKUP$1" "$1"; else sudo rm -f "$1"; fi
}

etc_post() {
  local d restart=() sysctl='' udev='' hwdb='' reload=''
  for d; do
    case $d in
      /etc/sysctl.d/*) sysctl=1 ;;
      /etc/udev/hwdb.d/*) hwdb=1 ;;
      /etc/udev/rules.d/*) udev=1 ;;
      /etc/systemd/system/* | /etc/systemd/user/*) reload=1 ;;
      /etc/tmpfiles.d/*) sudo systemd-tmpfiles --create "$d" ;;
      /etc/ananicy.d/*) restart+=(ananicy-cpp) ;;
      /etc/fail2ban/*) restart+=(fail2ban) ;;
      /etc/nftables.conf) restart+=(nftables) ;;
      /etc/keyd/*) restart+=(keyd) ;;
      /etc/systemd/journald.conf.d/*) restart+=(systemd-journald) ;;
      /etc/ssh/*)
        if ! sudo sshd -t; then etc_restore "$d"; die "sshd rejected $d — rolled back"; fi
        restart+=(sshd) ;;
      /etc/systemd/zram-generator.conf | /etc/modules-load.d/* | /etc/environment | \
        /etc/security/limits.d/* | /etc/NetworkManager/*) reboot_for "$d" ;;
    esac
  done
  [[ -n $sysctl ]] && sudo sysctl -q --system
  [[ -n $hwdb ]] && sudo systemd-hwdb update
  [[ -n $hwdb$udev ]] && sudo udevadm control --reload && sudo udevadm trigger
  [[ -n $reload ]] && sudo systemctl daemon-reload
  ((${#restart[@]})) && sudo systemctl try-reload-or-restart "${restart[@]}"
  return 0
}

apply_etc() {
  local dest src mode file changed=() n
  while read -r dest src mode; do
    [[ -f $CONF/$src ]] || die "etc.conf names a missing file: $src"
    file=$(etc_render "$src")
    if etc_same "$dest" "$file" "$mode"; then ok "$dest"; rm -f "$file"; continue; fi
    etc_validate "$dest" "$file" || die "$src failed validation — not installed"
    if sudo test -e "$dest"; then
      n=$(sudo diff "$dest" "$file" | grep -c '^[<>]' || true)
      sudo install -d -m 700 /etc/.setup-backup
      sudo mkdir -p "$ETC_BACKUP${dest%/*}"
      sudo cp -a "$dest" "$ETC_BACKUP$dest"
      did "$dest ($n lines changed, old copy in $ETC_BACKUP)"
    else
      did "$dest"
    fi
    sudo install -D -o root -g root -m "$mode" "$file" "$dest"
    rm -f "$file"
    changed+=("$dest")
  done < <(etc_entries)
  etc_post "${changed[@]}"
}

check_etc() {
  local dest src mode dir file d0=$DRIFT S=()
  sudo -n true 2>/dev/null && S=(sudo -n)
  while read -r dest src mode; do
    dir=${dest%/*}
    if ((!${#S[@]})) && [[ -d $dir ]] && { [[ ! -x $dir ]] || [[ -e $dest && ! -r $dest ]]; }; then
      warn "can't verify $dest without sudo (run sudo -v, then check again)"; continue
    fi
    file=$(etc_render "$src")
    if ! "${S[@]}" test -e "$dest"; then drift "missing $dest"
    elif ! "${S[@]}" cmp -s "$file" "$dest"; then drift "differs $dest"
    elif [[ $("${S[@]}" stat -c %a "$dest") != "$mode" ]]; then drift "mode $dest (want $mode)"
    fi
    rm -f "$file"
  done < <(etc_entries)
  ((DRIFT > d0)) || ok "/etc matches etc.conf"
}

#!/usr/bin/env bash
# heatsync crisp — apply vivaldi 8 config to the live profile.
# idempotent: backs up, closes vivaldi, patches Preferences (atomic), relaunches.
# pref keys mined from /opt/vivaldi/resources/vivaldi/prefs_definitions.json.
set -euo pipefail

PROFILE="$HOME/.config/vivaldi"
PREFS="$PROFILE/Default/Preferences"
CSS_DIR="$HOME/sync/config/vivaldi/ui"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="$PROFILE/_hs-backup-$TS"

command -v jq >/dev/null || { echo "FATAL: jq not installed"; exit 1; }
[ -f "$PREFS" ] || { echo "FATAL: no Preferences at $PREFS"; exit 1; }
[ -d "$CSS_DIR" ] || { echo "FATAL: css dir missing: $CSS_DIR"; exit 1; }

# 1. backup ----------------------------------------------------------------
mkdir -p "$BACKUP"
cp -a "$PREFS" "$BACKUP/Preferences"
[ -f "$PROFILE/Local State" ] && cp -a "$PROFILE/Local State" "$BACKUP/Local State"
echo "backup → $BACKUP"
snapper -c home create-pre --description "vivaldi-config $TS" >/dev/null 2>&1 \
  && echo "snapper pre-snapshot taken" || true

# 2. capture the running session's wayland env (for a clean relaunch) ------
VPID="$(pgrep -xo vivaldi-bin 2>/dev/null || true)"
ENVFILE="$(mktemp)"
if [ -n "${VPID:-}" ] && [ -r "/proc/$VPID/environ" ]; then
  tr '\0' '\n' < "/proc/$VPID/environ" \
    | grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DISPLAY|XDG_SESSION_TYPE|DBUS_SESSION_BUS_ADDRESS|XAUTHORITY)=' \
    > "$ENVFILE" || true
fi

# 3. close vivaldi so it flushes prefs and won't clobber our edit ----------
if pgrep -x vivaldi-bin >/dev/null; then
  echo "closing vivaldi…"
  pkill -TERM -x vivaldi-bin 2>/dev/null || true
  for _ in $(seq 1 30); do pgrep -x vivaldi-bin >/dev/null || break; sleep 0.5; done
  pkill -KILL -x vivaldi-bin 2>/dev/null || true
  sleep 1
fi

# 4. patch Preferences (atomic, validated) ---------------------------------
TMP="$(mktemp)"
jq --arg css "$CSS_DIR" '
    # --- crisp UI ---
    .vivaldi.appearance.css_ui_mods_directory = $css
  | .vivaldi.theme.use_animation              = false
  | .vivaldi.appearance.density               = false
  | .vivaldi.menu.compact                     = true
  | .vivaldi.theme.simple_scrollbar           = true
    # --- privacy (no keystroke/IP phone-home; VPN-safe webrtc) ---
  | .search.suggest_enabled                           = false
  | .vivaldi.address_bar.search.direct_match_enabled  = false
  | .webrtc.ip_handling_policy                        = "default_public_interface_only"
    # --- declutter (kill promo surfaces on the start page) ---
  | .vivaldi.dashboard.top_sites_hide_suggestions          = true
  | .vivaldi.biscuit.promote                               = false
  | .vivaldi.startpage.speed_dial.tracker_suggestion_show  = false
    # --- clean-exit guard so no crash bubble on relaunch ---
  | .profile.exit_type                        = "Normal"
  | .profile.exited_cleanly                   = true
' "$PREFS" > "$TMP"

if jq -e . "$TMP" >/dev/null 2>&1 && [ -s "$TMP" ]; then
  mv "$TMP" "$PREFS"
  echo "preferences patched:"
  jq -r '"  css_ui_mods_directory = \(.vivaldi.appearance.css_ui_mods_directory)",
      "  use_animation         = \(.vivaldi.theme.use_animation)",
      "  density(compact)      = \(.vivaldi.appearance.density|not)",
      "  menu.compact          = \(.vivaldi.menu.compact)",
      "  simple_scrollbar      = \(.vivaldi.theme.simple_scrollbar)",
      "  search.suggest        = \(.search.suggest_enabled)  (off=private)",
      "  direct_match          = \(.vivaldi.address_bar.search.direct_match_enabled)",
      "  webrtc.ip_handling    = \(.webrtc.ip_handling_policy)",
      "  start-page promos     = hidden"' "$PREFS"
else
  echo "FATAL: jq produced invalid output — Preferences left untouched"
  rm -f "$TMP"; exit 1
fi

# 5. relaunch with the captured session env, detached ----------------------
if [ -s "$ENVFILE" ]; then set -a; . "$ENVFILE"; set +a; fi
rm -f "$ENVFILE"
setsid vivaldi-stable --ozone-platform=wayland >/dev/null 2>&1 </dev/null &
disown 2>/dev/null || true
sleep 3
if pgrep -x vivaldi-bin >/dev/null; then
  echo "vivaldi relaunched ✓  (restart once more if css doesn't show — first load registers the mods dir)"
else
  echo "WARN: relaunch not detected. config IS applied — just open vivaldi manually."
fi

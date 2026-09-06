# vivaldi config — heatsync crisp

version-controlled vivaldi 8 setup. square, zero-motion, dense, terminal palette.
applied to the live profile by `apply.sh`; the css lives in `ui/` and is loaded
by vivaldi directly (no rebuild step).

## what it does

**ui css** (`ui/custom.css`) — cosmetic chrome tweaks, injected by vivaldi:
- squares every corner in the browser chrome
- flattens transitions (no slide/fade jank)
- orange #ff8700 active-tab edge + address-field focus ring
- minimal square scrollbars, square favicons, no ui shadows

**preferences** (set by `apply.sh`, exact keys mined from vivaldi's own
`prefs_definitions.json` — not guessed):

| pref key | value | effect |
|---|---|---|
| `vivaldi.appearance.css_ui_mods_directory` | `~/sync/config/vivaldi/ui` | enables the css above |
| `vivaldi.theme.use_animation` | `false` | kills ui animations (official path) |
| `vivaldi.appearance.density` | `false` | compact ui density |
| `vivaldi.menu.compact` | `true` | compact menu layout |
| `vivaldi.theme.simple_scrollbar` | `true` | thin scrollbars |
| `search.suggest_enabled` | `false` | privacy — no keystroke phone-home to the search engine |
| `vivaldi.address_bar.search.direct_match_enabled` | `false` | privacy — no direct-match remote lookup |
| `webrtc.ip_handling_policy` | `default_public_interface_only` | privacy — no local-IP leak (VPN-safe; webrtc still works) |
| `vivaldi.dashboard.top_sites_hide_suggestions` | `true` | declutter — no suggested links |
| `vivaldi.biscuit.promote` | `false` | declutter — no vivaldia-game promo button |
| `vivaldi.startpage.speed_dial.tracker_suggestion_show` | `false` | declutter — promo off |

local address-bar history autocomplete is left ON (it's local, not a privacy leak —
only the remote keystroke suggestions were disabled). vertical tabs
(`vivaldi.tabs.bar.position`) left untouched — already set.

## apply

```bash
~/sync/config/vivaldi/apply.sh
```

it backs up `Preferences` + `Local State`, closes vivaldi, patches the keys
with jq (atomic write), then relaunches with the same wayland session and
restores the previous tabs (`session.restore_on_startup=1`). idempotent —
safe to re-run.

## privacy note (not auto-applied)

vivaldi sends a daily telemetry ping (version, cpu arch, screen res) to its
iceland servers — **no browsing data**, but it cannot be disabled in-app.
to silence it, block `update.vivaldi.com` + `stats.vivaldi.com` at dns/router.
left for you to decide since it touches network policy.

## reverting

remove the css dir pref (set `css_ui_mods_directory` to `""`) or just blank
`ui/custom.css`. the backup dir printed by `apply.sh` holds the pre-change
`Preferences`.

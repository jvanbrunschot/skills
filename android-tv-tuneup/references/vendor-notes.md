# Vendor notes and known quirks

Field notes from real devices. Add to this file when you learn something new about a
model — that's how the skill gets better.

## Contents
- Sharp AQUOS (MediaTek/MStar m7322, Android TV 11) — verified 2026-10
- Generic Android TV Home (com.google.android.tvlauncher)
- Package glossary (what common preinstalled packages are)

---

## Sharp AQUOS_TVE19A — product `tcbrae_a`, device `sindang`, Android 11, MediaTek M7322

- 1.3 GB RAM, `ro.config.low_ram=true`, 512 MB zram swap, 4 CPU (Cortex-A55), armeabi-v7a userspace.
- **Load average ~25 at boot, ~70 after days** — harmless. ~70 MStar/MediaTek kernel driver
  threads (`VMon_Task`, `DMX_Filt_Task`, `TU0_*`, `hdcp22_*` …) idle in state D. CPU was 86% idle.
- Thermal zones not exposed; cpufreq governor `interactive`, max 1.4 GHz, no throttling seen.
- `screencap` output is prefixed with driver log lines (`Init wrapper sys mutex successful`,
  `open mma dev failed`) — strip everything before the PNG header (`ui.sh shot` does this).
- Network debugging: once USB debugging is enabled in Developer options, port 5555 was open.

### ACR tracker `tv.anoki.acr.controller` (Anoki, `/system/priv-app/AnokiController`)
- 36–47 MB PSS, also uses CPU. Flags include **PERSISTENT**.
- `pm disable-user --user 0` → state sticks, its components/provider become unreachable
  (others log `Failed to find provider info for tv.anoki.acr.controller.support`) **but
  ActivityManager still starts the process at boot** ("Start proc … for added application").
- `am force-stop` / `kill` from shell: no effect / not permitted.
- `pm uninstall --user 0` → "Success", but **firmware reinstalls it for user 0 at next boot**
  (stays disabled-user; app data gets recreated). Net effect = same as disable-user.
- Conclusion: features blocked by disable-user, RAM not recoverable without root.
  The user may find a viewing-information/ACR consent toggle in the TV's privacy/terms settings.

### HbbTV
- Not in the system Settings app and no settings-provider key.
- Path (Dutch UI): Live TV (`com.mediatek.wwtv.tvcenter/.nav.TurnkeyUiMainActivity`) → `MENU`
  key → row **Tv-opties** → scroll right to **Geavanceerde opties** → **HBBTV-instellingen** →
  **HBBTV-ondersteuning** (English: TV options → Advanced options → HbbTV settings → HbbTV support).
- The Advanced options list has other toggles right above it (Blauw dempen, Interactiekanaal,
  MHEG PIN) and focus skips non-focusable rows — dump after every move.
- Turning it off persists across reboot but the engine (`teatro_tv_browser`,
  `hbbtv_content_shell`, ~38 MB, launched by vendor daemon `app_man`) still starts. It blocks
  broadcaster red-button apps; it does not free RAM.

### Other packages seen
- `fusion.android.tv.demo` = `/system/app/UMCShopMode` (retail/shop demo). Ran in background;
  `disable-user` stuck after reboot. Safe to disable.
- `uk.co.freeview.*`, `com.mediatek.tv.freeviewplay` — UK Freeview Play, already disabled by
  firmware outside the UK.
- `com.mediatek.partner.netflix` keeps `com.netflix.ninja` (~90 MB) warm for instant start;
  it also produces repeated SIGABRT tombstones (`NoSuchMethodError … TVCallback`) — harmless
  firmware bug.
- `com.android.tv.settings` is provided by `TvSettingsPlus` (vendor fork of TV Settings).
- Device preferences include **Detailhandelmodus** (retail mode) — check it's off if a demo runs.

---

## Android TV Home (`com.google.android.tvlauncher`, seen v7.7.15, system v6.10.5)

- Typically the largest app: ~165–210 MB PSS, of which up to ~100 MB is graphics.
- **Video/audio previews** live in the launcher's private SharedPreferences → not settable via
  adb without root. Drive the UI instead:
  `am start -n com.google.android.tvlauncher/.settings.HomeScreenSettingsActivity`
  Rows (Dutch / English): Kanalen aanpassen / Customize channels (initial focus) →
  Videovoorbeelden aanzetten / Enable video previews → Audiovoorbeelden aanzetten / Enable audio
  previews → Ontdekken: Services aanpassen, Contentvoorkeuren … → Apps opnieuw ordenen.
  Turning both previews off took the launcher from 166 → 127 MB (graphics 100 → 29 MB).
- User-facing path: gear icon → Apparaatvoorkeuren / Device Preferences → Startscherm / Home screen.
- **Home screen ads** — find them with `ui.sh dump` on the home screen:
  1. top "featured content" carousel (`fc_item`, `metadata_text` "Aanbevolen voor jou" /
     "Recommended for you", streaming-service logo, wide backdrop image top-right);
  2. sponsored rows lower down, tagged `ad_sponsor_tag` with text "Gesponsord" / "Sponsored".
  Served by Google,
  no setting to remove it. Options: alternative launcher (Projectivy Launcher
  `com.spocky.projengmenu`, FLauncher `me.efesser.flauncher`) + `pm disable-user
  com.google.android.tvlauncher` (undo: `pm enable`). Install the replacement *first* and confirm
  it opens, otherwise Home lands on `com.android.tv.settings/.system.FallbackHome`.
  Private DNS ad-blocking is unlikely to remove it (same Google endpoints as the rest of home).
- Disabling `com.google.android.videos` (Play Films) may affect the **Winkel/Shop** tab.

---

## Package glossary

| Package | What it is | Verdict |
|---|---|---|
| `tv.anoki.acr.controller` | Anoki ACR (viewing-data recognition) | disable-user (privacy); see Sharp notes |
| `com.samsung.*acr*`, `tv.alphonso.*`, `com.samba.*` | Other ACR vendors | disable-user, check persistence |
| `*shopmode*`, `*retail*`, `*demo*` | Store demo | disable-user |
| `com.google.android.katniss` | Google Assistant/search | keep (remote mic button) |
| `com.google.android.gms`, `com.android.vending` | Play services / Play Store | keep |
| `com.google.android.tvrecommendations` | Feeds home-screen recommendation rows | usually keep; disabling empties rows |
| `com.google.android.backdrop` | Ambient-mode screensaver | harmless; only runs when idle |
| `com.google.android.tungsten.setupwraith` | TV setup wizard | keep — disabling setup apps can break Home |
| `com.google.android.apps.mediashell` | Chromecast built-in | keep if they cast |

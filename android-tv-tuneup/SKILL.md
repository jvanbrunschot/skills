---
name: android-tv-tuneup
description: Diagnose and speed up a slow, laggy or sluggish Android TV / Google TV (Sharp, Philips, TCL, Sony, Hisense, Xiaomi, Chromecast, Shield, set-top boxes) over adb — memory/swap thrashing, bloatware, ACR viewing-data trackers, launcher previews and home-screen ads, HbbTV, storage, animation speed — applying only reversible changes and keeping a written log with undo commands. Use this whenever the user mentions their TV or TV box being slow, freezing, unresponsive, full of ads or bloat, or wants to debloat / tune / clean up an Android TV via adb, even if they only give an IP address and model.
---

# Android TV tune-up over adb

Goal: find out *why* the TV feels slow, explain it in plain language, then apply only the fixes
the user picks — every one reversible, verified, and written down with its undo command.

Most sluggish Android TVs are not CPU-bound. They are low-RAM devices (1–2 GB) that have been on
for days, with the launcher, a vendor tracker and a few streaming apps fighting for memory, so the
kernel spends its time swapping. Diagnose first; tune second; be honest that hardware is the
ceiling (a cheap streaming stick on HDMI often beats any amount of tuning).

## Bundled tools

Scripts live in `scripts/` next to this file (resolve the absolute path once and reuse it):

- `scripts/diagnose.sh <serial> [outdir]` — read-only report: device, RAM/swap, top processes by
  PSS, CPU, storage, animation scales, ANRs/tombstones, LMK kills, third-party apps, likely bloat.
- `scripts/ui.sh <serial> dump|key …|shot <png>` — read the on-screen UI (texts, focused row,
  toggle states), send remote-control key events, take a clean screenshot.
- `scripts/wait_boot.sh <ip:port>` — reconnect and wait for `sys.boot_completed` after a reboot.
- `references/vendor-notes.md` — known quirks per vendor/model, menu paths (incl. Dutch UI),
  and a package glossary. Read it once you know the brand, and **append to it** when you learn
  something new about a device.

Shell note: in zsh, `S="adb -s X shell"; $S cmd` fails (no word splitting). Use a function:
`S(){ adb -s "$SER" shell "$@"; }`.

## 1. Connect

```sh
adb connect <ip>:5555 && adb devices -l
```
If refused: ping the IP, then check `adb mdns services` (Android 11+ wireless debugging uses a
random port). If nothing is listening, give the user these on-TV steps and wait:
Settings → Device Preferences → About → click **Build** 7× → Developer options → **USB debugging**
on (and **Network debugging** if present) → accept the "Allow debugging" prompt on the TV with
"Always allow". If 5555 still stays closed: connect once by USB and run `adb tcpip 5555`.

## 2. Diagnose (read-only)

Run `scripts/diagnose.sh <serial> <scratchpad>/diag` and read it with these interpretations:

- **Thrashing signature** (the usual culprit): `ro.config.low_ram=true` or <2 GB RAM, swap mostly
  used, long uptime, and the latest ANR shows `kswapd0` and `mmcqd` (eMMC) high with many *major*
  page faults. That means "not enough RAM", not "slow CPU".
- **High load average is often fake** on MediaTek/MStar/Realtek TV SoCs: dozens of driver threads
  sleep in state D and count toward load. Trust `%idle` in top instead.
- **Biggest PSS consumers** — typically the launcher (100–200 MB, much of it graphics from
  previews), a vendor ACR tracker, HbbTV browser, streaming apps kept warm.
- **Storage** under ~25% free slows eMMC writes; caches are often several hundred MB.
- **usagestats** only covers a recent window — a `1970-01-01` last-used time means "no data",
  not "never used". Ask the user which apps they use rather than inferring it.
- Look up every unfamiliar package before proposing to touch it (glossary in vendor-notes).

## 3. Report, then let the user choose

Present findings as a short table (process → RAM → what it is), call out false alarms explicitly,
then offer fixes ranked by impact with the trade-off of each. Use AskUserQuestion with
multiSelect so the user picks. Don't change anything before they choose — it's their TV, and some
fixes have visible side effects (lost red-button services, missing home rows).

## 4. Apply fixes — the reversibility discipline

For every change:
1. **Record the before-state** (setting value, `enabled=` state from `dumpsys package`, version).
2. Apply it.
3. **Verify** it took effect — and for anything that should survive a reboot, verify *after* a
   reboot. Vendor firmware frequently undoes or ignores changes (see below).
4. **Log it** in `CHANGES.md` in the working directory (see template) with exact commands, before
   → after, measured effect, and the undo command. Update the log after every step, including
   things that did not work — the user relies on it to undo things months later.

Only use reversible operations: `settings put`, `pm disable-user --user 0` (undo `pm enable`),
`pm uninstall --user 0` for system apps (undo `cmd package install-existing <pkg>`), `pm uninstall`
only for user-installed apps the user named (undo = Play Store). Never `pm clear` an app the user
didn't ask about, never touch Play services / Play Store / the setup wizard / the only launcher.

### Fix catalogue (roughly by impact)

| Fix | How | Notes |
|---|---|---|
| Reboot | `adb reboot` then `scripts/wait_boot.sh` | Clears days of swap. Recommend a weekly restart as a habit. |
| Launcher previews off | UI-driven (see §5) | Big graphics-memory win; prefs are private, no adb key. |
| Disable ACR / tracker | `pm disable-user --user 0 <pkg>` | Privacy + RAM. Check `flags=[… PERSISTENT …]`: persistent apps may still start at boot. |
| Disable shop demo / dead vendor apps | `pm disable-user --user 0 <pkg>` | Confirm what it is first. |
| Uninstall unused user apps | `pm uninstall <pkg>` | Only the ones the user names. |
| Free storage | `pm trim-caches 4G` + `sm fstrim` | Harmless; caches rebuild. Report free % before/after. |
| Faster animations | `settings put global {window,transition}_animation_scale 0.5`, `animator_duration_scale 0.5` | Perceived snappiness. If a key was `null` before, undo is `settings delete global <key>`. |
| HbbTV off | Vendor TV menu (UI-driven) | Blocks red-button apps; on some firmware the engine keeps running anyway. |
| Home-screen ad carousel | Alternative launcher + disable stock launcher | No setting exists. Install and test the new launcher *before* disabling the old one. |

### Things that commonly don't stick (verify!)

- Persistent priv-apps (e.g. ACR) get started by ActivityManager at boot even when disabled; shell
  can't `kill` or `force-stop` them. Disabling still blocks their components.
- Some firmware **reinstalls** `pm uninstall --user 0`'d system apps at boot.
- Vendor daemons can launch native processes (e.g. HbbTV engine) regardless of the setting.
When this happens, say so plainly, log it, and stop — don't escalate to riskier tricks.

## 5. Driving the TV UI over adb

Many settings (launcher previews, HbbTV, picture options) are only reachable through the UI.

1. Open the screen directly when you know the activity
   (`am start -n <pkg>/<activity>`; find candidates with
   `dumpsys package <pkg> | grep -oE '<pkg>/[A-Za-z0-9_.]+'`), otherwise navigate from
   `am start -a android.settings.SETTINGS` or the vendor Live TV app + `MENU`.
2. `scripts/ui.sh <serial> dump` → see texts, the `>> FOCUSED` row, and toggle states.
3. Move with `ui.sh <serial> key DPAD_DOWN` (one step at a time near the target), **dump again,
   confirm the focused row is the intended one**, only then `key DPAD_CENTER`. Lists skip
   non-focusable rows and scroll, so counting key presses is unreliable — neighbouring toggles are
   often things you must not flip.
4. Dump once more to confirm `checked=` changed; close and reopen the screen to confirm it
   persisted. Leave the TV on the home screen (`key BACK … HOME`) when done.
5. The UI is in the TV's language (e.g. Dutch: Startscherm = Home screen, Apparaatvoorkeuren =
   Device Preferences, Geavanceerde opties = Advanced options). Match by meaning and position.
6. Screenshots: `ui.sh <serial> shot <scratchpad>/x.png`, then Read the PNG. Useful to *see*
   things like ad banners. Playing DRM video may come out black.

The user may be watching the TV — opening Live TV or menus is visible on screen, so mention it.

## 6. Wrap up

Final message: what was changed (with measured before → after), what didn't work and why, what
remains possible, and the honest hardware verdict. Point to `CHANGES.md` for undo.

## CHANGES.md template

````markdown
# <Brand Model> (Android TV <ver>) — tuning log

Device: `<ip:port>`, build `<fingerprint>`
Connect first: `adb connect <ip:port>`

## <YYYY-MM-DD>

### Diagnosis
- <RAM, low_ram flag, uptime, swap use, ANR evidence, top consumers, false alarms>

### Change N — <short title>
| Setting / package | Before | After |
|---|---|---|
| … | … | … |

```sh
<exact commands run>
```
Result: <measured effect, verification incl. after reboot>

Undo:
```sh
<exact undo commands>
```

### Not changed (options for later)
- …
````

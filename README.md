# Liquid (Gl)ass 12

iOS 12 port of **Liquid (Gl)ass** by dylv (https://github.com/winaviation-tweaks/liquidass), made for the
iPod touch 6th generation (arm64, rootful, iOS 12.x).

Licensed under **CC BY-NC 4.0** like the original (see `LICENSE`). Non-commercial use only.
Changes from the original: rewritten renderer (stock iOS 12 blur instead of backboardd refraction
filters), only the dock / folder / banner hosts kept, rootful arm64 build, crash-loop guard.

## What it does
Glass-style frosted blur + tint + specular rim on: dock, home screen folder icons, open folders,
notification banners. Lock screen / Notification Center platters are supported but **off by default**
(many layers on an A8).

## Metal glass (LiquidGlassKit) in SpringBoard
The dock, banners and open folders can use LiquidGlassKit's real Metal glass (refraction, dispersion, glare)
instead of the plain blur. Folder icons stay on the blur by default because there can be ~16 per page.
Settings > Liquid (Gl)ass 12 > Metal glass has a master switch and one per host.

* Loaded from `/Library/PreferenceBundles/LiquidAss12Prefs.bundle/LGK/LGKCore.dylib` (same dylib as Settings).
* Draws at 30 fps and pauses when the panel is hidden; at most 6 Metal views at a time.
* If anything is missing or fails (dylib, Metal, shader compile) that host silently uses the blur renderer.
* If SpringBoard goes down within ~12 s of Metal starting, Metal turns itself off
  (`/var/mobile/liquidass12-nometal`) and the blur renderer is used. "Re-enable Metal glass" in Settings
  (or deleting that file) turns it back on.

## Safety
* Never touches backboardd. No render-server hooks.
* Waits 3 s after SpringBoard starts before touching any view.
* All work is wrapped in try/catch; stock views are hidden, never removed, and restored when needed.
* Crash-loop guard: 3 SpringBoard starts within 60 s without reaching a stable state writes
  `/var/mobile/liquidass12.disabled` and the tweak stops loading.
  Delete that file in Filza and respring to re-enable.
* You can also create `/var/mobile/liquidass12.disabled` yourself to turn it off.

## Debug log
`/var/mobile/liquidass12-debug.txt` (capped at 120 KB). It contains one view-tree dump per host the first
time it is seen. Send that file if a host does not get glass.

## Settings
Settings > Liquid (Gl)ass 12 (needs PreferenceLoader). Glass switches for each host, glass sliders for
Quality / Blur / Rim, and a Respring button. Changes apply after a respring.
The pane writes `com.jjlulz.liquidass12`; AltList is not needed.

### LiquidGlassKit controls
The switches and sliders are LiquidGlassKit's `LiquidGlassSwitch` / `LiquidGlassSlider` (by Alexey Demin,
https://github.com/DnV1eX/LiquidGlassKit), ported to iOS 12: iOS 13+ colors replaced, iOS 14/26-only API and
the factory protocols removed, shaders compiled at runtime. They are built as a separate Swift dylib
(`scripts/build-lgk.sh`) and loaded by the Settings bundle with `dlopen`.
They only run inside Settings, never in SpringBoard.

If the dylib is missing, fails to load, Metal is unavailable, or the last attempt crashed Settings, the pane
automatically uses simpler Objective-C glass controls instead.
* force the fallback: create `/var/mobile/liquidass12-nolgk`
* log: `/var/mobile/liquidass12-prefs-debug.txt`
* Needs iOS 12.2+ (Swift runtime).

| key | type | default |
|---|---|---|
| Global.Enabled | bool | true |
| Dock / FolderIcon / OpenFolder / Banner `.Enabled` | bool | true |
| Notification.Enabled | bool | **false** |
| Quality | float 0.3-1.0 | 1.0 (lower = cheaper) |
| Blur | float multiplier 0.5-2.0 | 1.0 |
| Rim | float multiplier 0-2.0 | 1.0 |

# Stand Up

A tiny macOS menu bar app that gets you off the chair and keeps you hydrated.

Sit for 25 minutes → Stand Up reminds you → press **I'm up!** and a 5‑minute move break starts (or **Snooze 5 min**).
Every break nudges you to drink a glass of water, and everything is logged so you can see how your days, weeks and months look.

Native Swift (AppKit + SwiftUI), no dependencies, ~0 % CPU and ~15 MB of memory while idle.

## Features

- **Menu bar timer** – a chair icon with the minutes left. Click for the panel, right‑click for quick actions.
- **Stand‑up reminder** – a soft chime, the icon turns orange and the panel opens by itself without stealing focus. Repeats gently if ignored.
- **Move breaks** – a 5‑minute countdown with a small movement tip; the sitting timer restarts automatically.
- **Water tracker** – log glasses with one click (glass size is configurable, default 250 ml), progress bar towards your daily goal, a nudge to drink on every break.
- **Personal water goal** – enter sex, age, weight, height, activity and climate; the app shows a transparent, step‑by‑step estimate (see below).
- **Analysis** – Today / Week / Month / 6 Months / Year / All time: focus time, break time, breaks, snoozes, water (ml and glasses), daily averages, days the water goal was met, water streak, breaks per focus hour, and charts.
- **CSV export** of the full history.
- **Smart away detection** – locking the screen or sleeping the Mac for a full break length counts as a break.
- Launch at login, adjustable durations, menu bar display (icon / minutes / mm:ss), sounds on/off.

## How the water goal is calculated

1. **Weight rule:** 35 ml/kg (age ≤ 55), 30 ml/kg (56–75), 25 ml/kg (> 75).
2. **Body‑surface rule:** 1,500 ml per m² of body surface area (Mosteller formula, uses height and weight).
3. The average of both is the total daily water need; about **20 % comes from food** (EFSA 2010), the rest from drinks.
4. The result is never below the **EFSA adequate intake from drinks**: 2.0 L (men) / 1.6 L (women).
5. Extras: activity (+250 / +500 / +1000 ml, after ACSM sweat‑replacement guidance), climate (+250 / +500 ml), pregnancy (+300 ml) or breastfeeding (+700 ml) per EFSA.

You can always override it with your own goal. This is an estimate for healthy adults, not medical advice.

## Build & install

Requires macOS 13+ and the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/yskarakas/StandUp.git
cd StandUp
./build.sh --install   # builds "Stand Up.app", copies it to /Applications and launches it
```

`./build.sh` without `--install` only builds the app next to the script.

## Data

History is stored locally in `~/Library/Application Support/StandUp/history.json`, settings in the app's user defaults. Nothing leaves your Mac.

## Uninstall

Quit the app (right‑click the menu bar icon → Quit), then delete `/Applications/Stand Up.app` and `~/Library/Application Support/StandUp`.

## Inspiration

Inspired by Barış Özcan's article [“Oturmak yeni sigara mı?”](https://barisozcan.com/yazi/oturmak-yeni-sigara-mi/) on why short, regular movement breaks matter.

## License

MIT

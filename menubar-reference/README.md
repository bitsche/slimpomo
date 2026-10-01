# Deeeep – menu-bar icon reference ("mini tank")

The exact target for the menu-bar icon. 18 × 18 pt canvas, black on transparent (template image).

- `svg/` – vector source of every state. **Draw exactly these paths** (same coordinates) with NSBezierPath / Path.
- `png/` – rendered references at 1× (18 px) and 2× (36 px).
- `menubar-reference-sheet.png` – all states enlarged and in light / dark menu bars.
- `gen.py` – generates the SVGs. `level_y()` is the water line. `sun_cy()` is the rising sun.

## Geometry (viewBox 0 0 18 18)
- Tank: rect x 2.5, y 2.5, 13 × 13, rx 3, stroke 1.5, round caps/joins.
- Idle wave: `M4 12.5 q1.25 -1.2 2.5 0 t2.5 0 t2.5 0 t2.5 0`, stroke 1.5.
- Water (work): `M0 y q2 -1.4 4 0 t4 0 t4 0 t4 0 t4 0 V18 H0Z`, filled, clipped to the tank rect;
  `y = 13.25 − 7.8 × level` (level 0…1 = elapsed ÷ duration). Draw the tank outline on top.
- Work paused: same water at fill alpha 0.4 + pause bars `M7 6 V12 M11 6 V12`, stroke 1.8, round caps, full alpha.
- Break: no tank. Sea line `M2 13 q1.75 -1.3 3.5 0 t3.5 0 t3.5 0 t3.5 0`, stroke 1.5, round caps.
  Sun is a filled circle, cx 9, r 4, clipped to `y < 10.6` (the horizon, 1 pt above the sea line).
  `cy = 13.1 − 7.2 × progress` (progress 0…1 = elapsed ÷ break duration).
  Start is a 1.5 pt cap. End is the full disc just above the horizon.
- Break paused: the sun stays put at fill alpha 0.4, plus the sea line and pause bars `M7 4 V10 M11 4 V10`, stroke 1.8, full alpha.

## States
`idle`, `work-running-10`, `work-running-45`, `work-running-90`, `work-paused-45`,
`break-running-05`, `break-running-50`, `break-running-95`, `break-paused-50`.

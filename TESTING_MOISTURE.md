# State Controller 1.0.0.9 — optional moisture transfer test

This is the first integration build for Moisture System 2.0.0.5. No files in
Moisture System or GSI Silos are modified. State Controller detects Moisture
System at runtime; it is not a required dependency.

## Install

Back up your save and working mod ZIPs. Replace State Controller with the test
`FS25_TH_StateController.zip`. Keep exactly one State Controller copy in the mods
folder and retain the exact filename. Keep your working GSI Silos and original
Moisture System ZIPs. All multiplayer participants need the same test version.

## First test: Moisture System enabled

Use a copy of your save. Keep dryer productions OFF for this first test.

1. Unload corn with a known moisture percentage into the wet bin. The State
   Controller HUD should show liters followed by the moisture percentage.
2. Select another empty bin and unload corn with a different moisture. The
   first bin's value must not change.
3. Use State Controller's fill-type mover to transfer corn between bins. Moving
   into an empty bin should preserve its percentage. Mixing batches should
   average moisture and quality by the actual liters transferred.
4. Select an output bin and fill a trailer. Check that the trailer receives that
   bin's moisture, including the final load that empties the bin. Also try a
   partially filled trailer to check mixing.
5. Save, quit, and reload. Check the separate bin values again.
6. In multiplayer, compare the host and client HUD and join after grain is
   already stored. Both initial and incremental synchronization need in-game
   verification.

Existing controls: Right Shift + [ selects input; Right Shift + ] selects
output; Right Shift + backslash operates the fill-type mover (subject to your
key bindings).

## Second test: Moisture System disabled

Restart the test save with Moisture System unchecked. Check ordinary intake,
bin switching, transfers, trailer loading, and the existing dryer behavior.
Moisture percentages should disappear and no missing-mod error should occur.
Untouched grain retains saved moisture history. Adding untracked grain while
the mod is off clears that bin/crop's old history so it cannot be reused as if
the new grain had been measured.

## Scope and limitations

- Implemented: individual controlled-storage moisture and quality, intake,
  fill-type mover, loading-station trailer output, HUD, save/load, and storage
  network streams. Normal capacity/access decisions remain in the existing
  State Controller/game code. Owned-intake skip-sell protection remains intact.
- Not implemented: moisture-based propane drying, the Moisture System drying
  menu, pallets, automatic distribution, or separate moisture for external silo
  extensions. Start with GSI's own bins and direct trailer loading.
- The original dryer recipes still run as before. Their conversion to a
  separate Dry Corn fill type is NOT moisture drying in this test version.
- `--%` means no recorded history, such as grain already in an older save.
  When unknown-history grain is transferred/mixed, the integration uses Moisture
  System's default moisture and derived quality; that is an estimate, not a
  recovered harvest measurement. Start with freshly harvested grain to verify
  exact preservation.
- Automated tests simulate game storage and networking and exercise the actual
  uploaded Moisture System station hooks. FS25 itself is not available in this
  development environment; gameplay/multiplayer compatibility remains to test.

Please send the new `log.txt`, the bin selected for input/output, grain liters
and percentages before/after, and whether Moisture System was enabled.

## Developer verification

Run `texlua tests/moisture_test.lua` for the standalone tests. Pass an extracted
Moisture System 2.0.0.5 directory as the first argument to additionally exercise
its original LoadingStationExtension and SellingStationExtension files.

# State Controller 1.0.1.2 — Wet Bin drying and automatic output

Finished corn now moves automatically to the selected internal Output State
bin when Wet Bin moisture reaches 15%. Already-dry corn moves too: select a
different output bin and activate the dryer. This is batch drying, not a
continuous-flow simulation: wet grain stays in BIN01 until it reaches target.
Full, incompatible, inaccessible, or same-as-source outputs leave grain in
the Wet Bin and show no output space. Select another output to resume; waiting
or transferring finished grain consumes no propane. The dryer stops after the
Wet Bin empties. Incoming corn blends with existing output moisture and quality.

The manual mover now excludes input materials unsupported by the output state,
preventing Wet Bin's propane input from blocking a grain-only transfer.
Local tests pass; in-game testing of 1.0.1.2 is pending.

Fixes a startup ordering bug in 1.0.1.0: Moisture System initializes its crop
tracking in `onStartMission`, after saved placeables load. The adapter no longer
permanently rejects corn during recipe configuration; tracking is checked each
time the dryer runs. Static XML validation is unchanged.

Regression check: reload with 1,000 L corn at 15.2% in Wet Bin and 80,000 L
propane, then enable Moisture drying (15%). After approximately six game minutes,
corn should remain 1,000 L at 15%, using about 0.4 L propane (the whole-liter HUD
may still show 80,000 L). Corn should now be in the selected output bin;
unselected bins must remain unchanged. The startup fix was confirmed in-game
on 1.0.1.1.

This build adds Wet Bin drying for Moisture System 2.0.0.5. No files in
Moisture System or GSI Silos are modified. State Controller detects Moisture
System at runtime; it is not a required dependency.

## Install

Back up your save and working mod ZIPs. Replace State Controller with the test
`FS25_TH_StateController.zip`. Keep exactly one State Controller copy in the mods
folder and retain the exact filename. Keep your working GSI Silos and original
Moisture System ZIPs. All multiplayer participants need the same test version.

## First test: Moisture System enabled

Use a copy of your save. Keep the GSI folder/ZIP named `FS25_GSI_SILOS`.

The built-in GSI profile uses ONLY `BIN01` (Wet Bin) for grain and `TANK01`
for propane. `BIN04`, displayed as Storage Bin #1, is NOT the Wet Bin.
The dryer always dries in Wet Bin, then transfers the finished batch to the
selected Output State. Input selection does not change the drying source.

1. Put measured corn above 15% in the Wet Bin and propane in the propane tank.
2. Select an empty storage bin as Output State, then enable one of the existing
   GSI dryer productions in the production menu.
   With Moisture System active they are labeled **Moisture drying (15%)**.
3. Advance game time. The initial tuning removes 2 percentage points per game
   hour. At 15%, corn moves to the selected output. Corn remains corn and its total liters remain
   unchanged. As in Moisture System's own dryer, stored quality history remains
   unchanged; this does not guarantee a reset to the best sale grade.
4. Put wet corn in a different storage bin and select it for input/output.
   Only the Wet Bin should dry. Empty the propane tank: drying should pause.
5. Save/reload during drying. Check that grain, propane and moisture persist.
   Quit to the menu and check the log for the previous cleanup errors.
6. Try an output with only 400 L free and a 1,000 L finished batch. It should
   move 400 L and retain 600 L in Wet Bin. Choose a different output and verify
   the remaining 600 L moves without additional propane. Also test a bin
   holding another crop and Wet Bin selected as its own output.

Fuel tuning: 2 liters of propane per 1,000 liters of grain per percentage point
removed. Example: 1,000 liters at 24% takes 4.5 game hours and 18 liters of
propane to reach 15%. The existing operating cost is charged only for the time
actually drying. Partial fuel produces partial progress; dry/empty bins use
none. Starting both recipes does not double the drying rate for the same bin.

Also recheck the previously working transfer features:

- Unload corn with a known moisture percentage into the wet bin. The State
   Controller HUD should show liters followed by the moisture percentage.
- Select another empty bin and unload corn with a different moisture. The
   first bin's value must not change.
- Use State Controller's fill-type mover to transfer corn between bins. Moving
   into an empty bin should preserve its percentage. Mixing batches should
   average moisture and quality by the actual liters transferred.
- Select an output bin and fill a trailer. Check that the trailer receives that
   bin's moisture, including the final load that empties the bin. Also try a
   partially filled trailer to check mixing.
- Save, quit, and reload. Check the separate bin values again.
- In multiplayer, compare the host and client HUD and join after grain is
   already stored. Both initial and incremental synchronization need in-game
   verification.

Existing controls: Right Shift + [ selects input; Right Shift + ] selects
output; Right Shift + backslash operates the fill-type mover (subject to your
key bindings).

## Second test: Moisture System disabled

Restart the test save with Moisture System unchecked. Check ordinary intake,
bin switching, transfers, trailer loading, and the existing dryer behavior.
The original Corn-to-Dry-Corn conversion is retained, but its input must now be
the Wet Bin. Selecting another input pauses that legacy recipe. Output selection
works as before. These restrictions apply to the two GSI dryer recipes only.
Moisture percentages should disappear and no missing-mod error should occur.
Untouched grain retains saved moisture history. Adding untracked grain while
the mod is off clears that bin/crop's old history so it cannot be reused as if
the new grain had been measured.

## Scope and limitations

- Implemented: individual controlled-storage moisture and quality, intake,
  fill-type mover, loading-station trailer output, HUD, save/load, and storage
  network streams. Normal capacity/access decisions remain in the existing
  State Controller/game code. Owned-intake skip-sell protection remains intact.
- Added: Wet Bin-only propane drying and idempotent controller deletion with
  base Object cleanup to unregister it from the network. Stale triggers are
  not removed a second time.
- Not implemented: the Moisture System drying
  menu, pallets, automatic distribution, or separate moisture for external silo
  extensions. Start with GSI's own bins and direct trailer loading.
- `--%` means no recorded history, such as grain already in an older save.
  When unknown-history grain is transferred/mixed, the integration uses Moisture
  System's default moisture and derived quality; that is an estimate, not a
  recovered harvest measurement. Start with freshly harvested grain to verify
  exact preservation.
- The moisture dryer pauses on grain showing `--%`; it does not invent a
  measurement to charge for drying it. Use grain with a recorded percentage.
- Automated tests simulate game storage and networking and exercise the actual
  uploaded Moisture System station hooks. FS25 itself is not available in this
  development environment; gameplay/multiplayer compatibility remains to test.

Please send the new `log.txt`, the bin selected for input/output, grain liters
and percentages before/after, and whether Moisture System was enabled.

## Developer verification

Run `texlua tests/moisture_test.lua` for the standalone tests. Pass an extracted
Moisture System 2.0.0.5 directory as the first argument to additionally exercise
its original LoadingStationExtension and SellingStationExtension files.
Run `texlua tests/cleanup_test.lua` for teardown regression tests.

Other State Controller placeables can opt in using this child of a recipe's
`thStateController` element (values are fractions except the fuel rate):

```xml
<moistureDrying enabled="true" fillType="MAIZE" fuelFillType="PROPANE"
    storageId="BIN01" fuelStorageId="TANK01" target="0.15"
    ratePerHour="0.02" fuelPer1000LitersPerPoint="2" />
```

GSI's verified recipes get those defaults automatically. Other mods are not
matched by recipe name alone. If Moisture System is absent, original recipe
configuration is used.

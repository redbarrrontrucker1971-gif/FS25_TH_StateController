# Two-leg GSI test: State Controller 1.0.2.1 + GSI 0.0.2.1

Install BOTH updated ZIPs, named FS25_TH_StateController.zip and
FS25_GSI_SILOS.zip. Replace prior copies, including any extracted mod folders.
Use a backup/test save for the first run. Moisture System stays optional.
The GSI file is based on the user's 0.0.1.9 upload; all i3d files and mappings
are unchanged. No extra leg animation or sound has been added in this build.

## Controls and route

The existing Input State selector now chooses the receiving leg destination.
Output State chooses the trailer loading bin; it does not redirect dryer discharge.
Use the production menu to independently activate these three processes:

1. Receiving leg: Pit to Input State. All new grain unloading goes into Pit
   regardless of the selected bin. The receiving leg moves it to the selected
   input bin: Wet Bin, Loadout, or any storage bin. Choosing Pit itself waits.
2. Moisture drying (20%) / Grain Dryer. Only Wet Bin supplies the 1,000 L
   dryer chamber. A running batch is never topped up with fresh wet corn.
   Finished grain goes into the separate 1,000 L discharge hopper.
3. Dryer discharge: Storage Bin #1. Moves from the discharge hopper only to
   Storage Bin #1 (BIN04), regardless of Input or Output State. It never draws
   directly from Wet Bin. Full or incompatible Bin #1 pauses discharge; it
   resumes when that same bin has room.

Both legs can run together. For direct storage/bypass, select a storage bin as
Input State and run only the receiving leg. The dryer always takes Wet Bin
corn independently of Input State. Disable the old manual mover when testing
this route; it is still available for deliberate bin-to-bin transfers.

Start rates: each leg 10,000 liters per GAME hour. The XML's grainFlow
litersPerHour sets the rate. At 1x time a 1,000 L transfer takes six minutes.
Enabled legs wait on an empty source or a full/incompatible destination and
resume automatically when grain/space becomes available. They charge operating
cost only while moving grain. Use the production switches to shut them off.
The usual Missing materials / No output space statuses also describe waiting.

With Moisture System, corn dries at 2 percentage points per game hour to 20%,
consuming 2 L propane per 1,000 L corn per percentage point removed. Already
dry corn passes without more drying. Without Moisture System, the chamber
converts at up to 2,000 L/game hour: 200 L corn + 4 L propane -> 200 L CORN_DRY.
The new recipe configuration exposes propane as an input in both modes.

The on-foot State Controller panel lists Pit, Dryer chamber and Dryer
discharge hopper contents. The production storage list still follows the
selected input/output states; use the on-foot panel to inspect the buffers.
Chamber/hopper liters and moisture use the existing per-storage save/network
mechanisms; there is no grain stored in an unsaved Lua-only queue.

## In-game verification needed

- Receiving leg off: unload 2,000 L. Only Pit should increase. Start the leg
  and confirm gradual movement. Switch Input State between two storage bins.
- Route corn into Wet Bin. Start dryer and dry-grain leg. Check each buffer,
  total liters, propane, and destination moisture. With MS, do not expect the
  first output until the first small batch reaches 20%.
- Fill Storage Bin #1 or put another crop in it. Discharge must wait without
  losing grain. Changing Output State must not divert it. Empty Bin #1 and
  confirm discharge resumes into Bin #1 only.
- Stop each production separately; the other leg must remain operable.
- Save/reload with corn in both dryer buffers. Check liters and moisture.
- Repeat with MS disabled, checking CORN_DRY output and propane use.
- Compare host/client panel contents if testing multiplayer.

Local simulated tests exercise storage setters, moisture blending, rate limits,
capacity blocking, legacy conversion and moisture persistence. FS25 runtime,
savegame migration and multiplayer still require gameplay validation.

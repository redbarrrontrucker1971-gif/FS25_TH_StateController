# AGI pit intake: AGI 1.0.0.7 + State Controller 1.0.2.3

Install both ZIPs. GSI stays unchanged.
Grain deliveries always enter Pit (BIN01); propane enters TANK01.
Choose a destination with Input State, then activate "Receiving leg: Pit to Input State"
in the production menu. Leave it off to hold deliveries in the pit. At 1x time,
10,000 L per game hour means 1,000 L takes six minutes. Full or incompatible bins
pause the leg; it resumes when space is available. Selecting Pit itself waits.
Output State continues to select trailer loading and finished dryer output.
Keep the old manual mover off unless you deliberately want a separate transfer.

Wet Bin (BIN02) still dries regular corn to 20% with Moisture System, transferring
finished corn to the selected output. Without Moisture System, the existing
MAIZE -> MAIZE2 recipe remains. Moisture System itself is unchanged.

Test unload with both selectors pointing elsewhere, leg off/on, full destination,
propane delivery, save/reload, and drying with and without Moisture System.
Local simulated checks passed; gameplay and multiplayer still need testing.

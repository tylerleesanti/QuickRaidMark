# QuickRaidMark

A radial raid-marker menu for World of Warcraft. Hold a key, flick the mouse toward a marker, release. Works in combat.

## Setup

Bind a key under **Options → Keybindings → AddOns → QuickRaidMark → "Quick Raid Mark Menu"**, or click the Skull button on the minimap to open the settings window and press **Change keybind** to go straight there. Drag the minimap button to move it.

## Using it

- **Hold the key** to open the menu at your cursor.
- **Point at a marker and release** to mark your target.
- **Quick tap** (release without moving) marks **Skull**, which sits in the centre.
- **Bottom slot (red X)** clears the target's marker.
- **Number keys** while the menu is open mark the unit **under your mouse** (or your target, if the mouse isn't over a unit) and keep the menu open. Keep holding the menu key, point at one mob after another and press a number for each, then release the key to close the menu. Releasing after using number keys only closes the menu.
  1 Skull, 2 Cross, 3 Square, 4 Moon, 5 Triangle, 6 Diamond, 7 Circle, 8 Star, 9 clear.
  The small number in each slice shows its key.
- **No target?** QuickRaidMark marks the unit under your cursor when you press the key, without leaving it targeted.

### Ground markers

- **Press Ctrl** while the menu is open to switch between raid and ground markers. The label under the menu shows which set is active, and the menu remembers it until you press Ctrl again. Prefer Alt or Shift? Click the minimap button and pick one under **Raid/ground swap key** in the settings window. Raid markers are the default: after 5 minutes without using the menu, it goes back to raid markers.
- On ground markers the menu turns dark brown and each marker sits on a coloured circle, so you can tell the sets apart at a glance.
- On ground markers, releasing (or a number key) gives you a targeting circle: click the ground where the marker goes. Key 9 removes all ground markers. After using number keys, releasing over the clear slot still removes all ground markers.
- The clear slot removes all ground markers.

## Notes

- In a raid you need to be leader or assistant to set markers.
- Choosing the marker a target already has does not remove it (that is how the game's marking command works); use the clear slot.

## License

MIT. See [LICENSE](LICENSE).

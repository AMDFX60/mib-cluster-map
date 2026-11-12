# MIB Cluster Map for Skoda

Puts the Android Auto map (Google Maps, Waze) on the Virtual Cockpit of a
Skoda with the Harman MIB2.5 High head unit (firmware train `MHI2_ER_SKG13_`).

This is a fork of
[MacsInSpace/mib-cluster-map](https://github.com/MacsInSpace/mib-cluster-map),
which does the real work: the hook, the player, the installer and the support
for VW, SEAT and Audi all come from there (see [Credits](#credits)). This fork
tunes it for the Skoda cockpit and adds switches to try out the map layout
from the green menu. It is developed and car-tested on a **Skoda Superb**:

| | |
|---|---|
| Head unit software | MU1440 |
| Firmware train | `MHI2_ER_SKG13_P4526` |
| Cockpit map window | 1010×376 |

It installs from an SD card as a software update. No toolbox, laptop or
command line is needed. The installer checks the unit and installs what fits
it: the map, the arrows, or nothing. If nothing fits, it collects the files
needed to add your unit and changes nothing.

No VNC and no app on the phone. The phone sends its own cluster video stream,
and the head unit passes it to the cockpit the same way it sends the built-in
navigation map.

> [!CAUTION]
> This modifies system files on the head unit. A mistake can leave the phone
> connection, or the whole centre screen, not starting. Use it only on a car
> you own, keep the SD card, keep the battery charged, and never install or
> test while driving. No warranty of any kind. Read
> [Safety and recovery](docs/Install.md#safety-and-recovery) first.

## What this fork changes

Based on upstream **v1.2.1** (merged in 1.2.2), with its installer, fixes and
Android Auto features. Upstream took the sharper map, the fix for insets above
127 and the player priority from this fork; the fork has since moved on to a
720p picture. What differs:

| | Upstream | This fork |
|---|---|---|
| Picture (`CLUSTERMAP_720P`) | 800×480 for the cluster, stretched to the 1010×376 window (or upstream's sharper map, squeezed and stretched) | **720p, 1:1**: the phone sends 1280×720 with margins that leave exactly the 1010×376 window, shown without any scaling. Car-tested (1.2.2-beta3): sharper than the sharper map, which this fork no longer offers |
| Colours | Every stream taken as full range (0-255) | **As the stream says**: limited range BT.709 from the phone, so deeper blacks and more contrast. `GAL_PLAYER_COLOR=old` for the previous look |
| Map size (`GAL_SECONDARY_DPI`) | `auto`: 125 on a Skoda | **110** (139 after the 720p scaling): smaller text and a compact turn card |
| Turn card (`GAL_SECONDARY_INSETS`) | `auto`: 40,127,127,127 on a Skoda, the card at the top | **100,138,320,320: hidden**. Google Maps leaves its card out when the space it gets is too short for it, so the map shows without the green card, with the arrival time in a line at the bottom and the car just above it. The green menu shows the card again, or moves the car higher, for a test |
| Cockpit window (`GAL_PLAYER_WINDOW`) | Guessed from the make when the display manager does not list it | Also preset to **1010×376** |
| Player priority (`GAL_PLAYER_PRIORITY`) | Unset (10) | **12**: a little higher, so the system's compositor holds up the cockpit map less |
| CarPlay map | Installed where the unit's CarPlay library fits | **None**. This fork is Android Auto only; installing it removes a CarPlay map an older package added, and CarPlay itself stays stock |
| Green menu | Status, logs, uninstall, sharper map, arrows switch | **Also** the 800×480 picture to compare, test positions for the turn card, the map size and the cockpit frame rate ([below](#green-menu-switches)) |
| Building | Linux, macOS | **Also Windows**: Git Bash and Docker Desktop |

Releases are named `mib-cluster-map_v1.1.2-skoda.zip`, test versions
`mib-cluster-map_v1.2.2-betaN-skoda.zip`.

### From upstream with 1.2.2

- **Installer:** firmware facts in `profiles.conf`, checked against the unit's
  own Android Auto program before anything is changed; missing tools reported
  first; several silent stops ("code 1") fixed; a `gal_dualscreen.conf` saved
  with Windows line endings is read in full; the untouched system config is
  always taken from the unit itself.
- **Your settings are kept:** lines you change in `gal_dualscreen.conf` on the
  card are carried over to the next package's install
  (`CLUSTERMAP_KEEP_SETTINGS=0` for a clean one). Green-menu tests still reset
  at each install.
- **Player:** reads the real cockpit window at its start, and writes a health
  line to its log once a minute (to tell a black picture from a stalled
  player).
- **Green menu:** works from either SD slot or a USB stick.
- **New, off by default:** `GAL_PRIMARY_DPI` (Android Auto's size on the
  centre screen), `GAL_CROP_TOP`/`GAL_CROP_BOTTOM` (manual crop of the 800×480
  frame), and the translation of Android Auto 1.6+ navigation messages
  for `GAL_DUALSCREEN_AAP_MINOR` 6 or 7. `CLUSTERMAP_TURN_INFO` and
  `CLUSTERMAP_MUSIC_INFO` (turn arrow and music on the cockpit beside the map)
  are only installed on trains where the arrows jar is known to work, which
  the Skoda `P4526` is not yet.
- **Autorun:** `Swdlautorun.txt` is on, so the update starts by itself when
  the card goes in; the installer switches it off when it finishes.

## Install

1. **Make the SD card.** Format a 2 to 32 GB card as FAT32. Download the zip
   from [Releases](../../releases) (or [build it](#building)) and copy
   everything inside it to the card:

   ```text
   (SD card)
   ├── ClusterMap/
   ├── Custom/
   ├── metainfo2.txt
   └── Swdlautorun.txt
   ```

   Put it in **SD slot 1**, with the other slot empty.
2. **Run the update.** Engine running or a charger connected. On most units
   the card starts the update by itself within a couple of minutes
   (`Swdlautorun.txt`; the installer switches it off again when it
   finishes). If it does not, hold **MENU** until the service screen
   appears, then `Software updates/versions` > `Update` > the SD card >
   **`MIB Cluster Map`**. Let it finish (a "Version back documentation"
   screen at the end is normal: press `Cancel`), then hold the power button
   for ten seconds to reboot. To stop the card starting on its own, rename
   `Swdlautorun.txt` to `_Swdlautorun.txt` (see the
   [Install guide](docs/Install.md#route-1-software-update)).
3. **Use it.** Plug in the phone, start a map, and switch the Virtual Cockpit
   to its map view with the steering wheel buttons.

The update writes what it did to `ClusterMap/update_result.txt` on the card.
It also adds a **ClusterMap** screen to the green engineering menu (hold MENU >
`Testmode` > `Green Developer Menu`) for status, logs, uninstall and the
switches below.

On the Skoda the installer also adds the `NavActiveIgnore` patch, without
which the cockpit drops the map as soon as the phone starts a route. The green
menu **Status** screen should then say `NavActiveIgnore: loaded`.

To update, run the update from the newer package the same way. An install
writes the card's settings again (plus the lines you changed on the card
before, see above) and so resets the green-menu tests.

The green menu and SSH routes, every setting, and recovery are in the
[Install guide](docs/Install.md).

**Uninstall:** green menu > `ClusterMap` > **Uninstall and restore original
state**, then reboot. Or, without the menu: on a computer, move
`UNINSTALL.txt` from the folder `to uninstall, move this file up one folder`
up into `ClusterMap`, and run the same update again.

## Green menu switches

Each changes only the unit's own copy of the settings (the frame rate: the
unit's copy of `NavActiveIgnore.jar`) and takes effect after a reboot. The turn card tests are measured for the 1010×376 window at DPI 110.

| Entry | What it does | On the Superb |
|---|---|---|
| 720p picture 1:1 (standard) | The phone draws the cockpit window's own pixels in a 1280×720 frame, shown without scaling | Car-tested (1.2.2-beta3): sharper. About 8 to 10 pictures a second there; beta4 copies only the visible part and logs where the time goes |
| Test: 800x480 picture (to compare) | Upstream's 800×480 frame with margins, stretched to the window. The 720p entry goes back | For comparing sharpness and smoothness |
| Test: show the turn card at the top | The card at the top, centred, the car below it (the settings before 1.1.2) | Car-tested up to beta12 |
| Test: show the turn card at the bottom | The card in a band at the bottom, between the two lower segments | Not tested yet |
| Test: hidden turn card, car higher | Still no card, the space 25 lines higher (`75,163,320,320`, the standard of 1.2.2-beta2 and beta3), so the car is further from the arrival line | Car-tested (beta12, 1.2.2-beta3): no card, the car visible, the arrival time in a line at the bottom |
| Turn card as installed (hidden) | Back to the installed settings: no card, the car nearer the arrival line at the bottom (`100,138,320,320`) | Not tested yet. A full-width space (beta4's "car lower" test) let Maps put the card at the side, so the space stays 160 wide |
| Test: map smaller / larger (DPI -10 / +10), Map size as installed | The map and its text smaller or larger, between DPI 80 and 170 | Not tested yet |
| Test: cockpit map 30 fps mode / Cockpit map 20 fps mode (standard) | The unit sends the cockpit its map picture 30 instead of 20 times a second (stock firmware: 10), through a copy of `NavActiveIgnore.jar` that differs only in that number. The idea comes from [omonob/MHI2-Carplay-Maps](https://github.com/omonob/MHI2-Carplay-Maps) | Not tested yet |

Moving the card to the left or right was tried in beta12 and dropped: Google
Maps keeps the card centred above the car, so the car and the whole view moved
with it.

## Status on the Superb (`P4526`)

| Part | State |
|---|---|
| Install by software update, green menu | Car-tested, beta8 to beta12 |
| Android Auto map, with and without a route | Car-tested |
| Automatic day/night | Car-tested (beta8), also by another owner ([upstream #41](https://github.com/MacsInSpace/mib-cluster-map/issues/41)) |
| Sharper map (1.1.1-beta9 to 1.2.2-beta3) | Car-tested (beta9); replaced by the 720p picture |
| 720p picture 1:1, colour range fix (from 1.2.2-beta3) | Car-tested (beta3): sharper, colours as the stream says (limited range BT.709). About 8 to 10 pictures a second: being looked into (beta4 logs the player's timing) |
| Android Auto version 1.5 (`GAL_DUALSCREEN_AAP_MINOR=5`, from beta11) | Car-tested (beta12): map and insets as before. Earlier tests ran at 7: go back to 7 if something stops working |
| Turn card hidden | Car-tested (beta12). The car lower of 1.1.2 to 1.2.2-beta1 (`134,104,0,0`) is car-tested too: the card stays hidden, but the car goes behind the cockpit's lower bar, out of sight, so 1.2.2-beta2 went back to the beta12 values; beta4 moves the space 25 lines down for a car nearer the arrival line (not tested yet) |
| Turn card at the bottom, map size | Not tested yet |
| Turn-arrows jar beside the map (`CLUSTERMAP_KEEP_ARROWS=1`) | Not tested on a Skoda |
| Cockpit map at 30 fps, player priority 12 (from 1.1.3) | Not tested yet |
| Upstream v1.2.1 base: installer, kept settings, player window check (from 1.2.2) | Not tested on the Superb yet; upstream's own releases run on many cars |
| `GAL_PRIMARY_DPI`, `GAL_CROP_TOP/BOTTOM`, Android Auto 1.6/1.7 with the translation | Not tested on a Skoda (off by default) |
| Turn arrow and music on the cockpit beside the map (`CLUSTERMAP_TURN_INFO`, `CLUSTERMAP_MUSIC_INFO`) | Not offered on `P4526`: the arrows jar is not known to work here yet |
| Hardware video decoding (`GAL_PLAYER_DECODER=hw`) | Fails and falls back to software decoding (upstream, under investigation) |

Not possible so far: moving the turn card without the car (Google Maps places
both in the same space), zooming the cockpit map from the steering wheel
([why](docs/Development.md#zoom)), and switching between the phone's map and
the car's map from the steering wheel.

## Will it work on my car?

| Car | Today |
|---|---|
| Skoda Superb, `MHI2_ER_SKG13_P4526` | **Map**, tested with this fork |
| Other Skoda with the Harman unit, `MHI2_ER_SKG13_` | Not tested. Run the update: the installer checks the real firmware, installs only what fits, and otherwise collects the files needed to add the unit (see [Getting your unit added](docs/Install.md#getting-your-unit-added)) |
| SEAT `MHI2_ER_SEG11_P4708` and `P4709` | Same 1010×376 window, so these settings may suit it; not tested with this fork |
| VW, Audi | The code is upstream's and still knows every unit it supports, but the settings here are tuned for the Skoda. Use [upstream's releases](https://github.com/MacsInSpace/mib-cluster-map/releases) |
| CarPlay | Not in this fork. Upstream has a CarPlay map |

You need the Virtual Cockpit for the map. The firmware train is on the green
menu **Status** screen. A unit whose train does not start with `MHI2_ER_`
(MIB2 Standard, for example, starts with `MST2_`) is a different unit and not
covered.

## Building

From Git Bash on Windows with Docker Desktop, or on Linux and macOS:

```bash
RELEASE_VERSION=v1.2.2-beta4-skoda ./build_local.sh
```

The package lands in `dist/` and its contents in `dist/sdcard/`. The head unit
replaces the green menu only for a higher version number, which
`RELEASE_VERSION` gives: `v1.1.1-beta12` is 11112, `v1.1.2` 11299,
`v1.1.3-beta1` 11301 and `v1.2.2-beta1` 12201, whatever follows (`-skoda`).
The first run builds FFmpeg once. Details are in
[Development](docs/Development.md) and at the top of `build_local.sh`.

## Documentation

| Page | For |
|---|---|
| [Install guide](docs/Install.md) | Install routes, the menu, settings, logs, safety and recovery, getting your unit added |
| [Development](docs/Development.md) | How it works, what was learned, adding a firmware, building |

## Reporting a problem

Skoda and anything this fork changes: open an issue
[here](https://github.com/AMDFX60/mib-cluster-map/issues), in German or
English. Everything else, and other cars: [upstream](https://github.com/MacsInSpace/mib-cluster-map/issues).
Say which car, firmware train and package, what you did and what you saw.
Attach the logs from green menu **Save logs to SD**, saved before rebooting,
and a photo of the cockpit helps. Read the logs first: the system log can
contain phone names and Bluetooth addresses.

## Credits

- **MacsInSpace** and the contributors of
  [mib-cluster-map](https://github.com/MacsInSpace/mib-cluster-map): the
  project this fork is based on, with its installer, green menu, firmware
  profiles and documentation.
- **chopinwong01**: [mhi2-android-auto-video-vc](https://github.com/chopinwong01/mhi2-android-auto-video-vc),
  the hook and player upstream is forked from. Its design notes and
  development story stay there.
- **andrewleech** and **OneB1t**: VcMOSTRenderMqb, the cluster rendering path
  the player derives from.
- **jilleb**, **olli991** and contributors: the MQB Coding MIB2 Toolbox. Its
  `NavActiveIgnore.jar` (contributed by andrewleech) and the signed header of
  its update metadata are bundled unmodified under `thirdparty/` (MIT).
- **adi961**: mib2-android-auto-vc, the turn-arrows jar. Bundled under
  `thirdparty/` (MIT) as the arrows mode, built from
  [upstream's maintained fork](https://github.com/MacsInSpace/mib2-android-auto-vc).
- **aberbic** ([Audi MHI2 AltScreen](https://github.com/aberbic/Audi-MHI2-Virtual-Cockpit-Altscreen-CarPlay-AndroidAuto)):
  the decoder layout the player's hardware-decoding path uses.
- **kkrvch** ([mib-std2-kombibridge](https://github.com/kkrvch/mib-std2-kombibridge)):
  the Android Auto 1.7 navigation decoder whose message layout and manoeuvre
  table upstream ported into `src/nav_translate.c`, with the author's
  permission.
- **harman-f** (via [M.I.B.](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)):
  the Audi build of `NavActiveIgnore.jar`, bundled unmodified under
  `thirdparty/navactiveignore-audi/` (GPL-2.0) for upstream's Audi support.
- **omonob** ([MHI2-Carplay-Maps](https://github.com/omonob/MHI2-Carplay-Maps)):
  the cockpit frame rate in `ChangeDataRateSequence`, the idea behind the
  30 fps switch.
- **Mr-MIBonk** ([M.I.B.](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)):
  the `Swdlautorun.txt` trigger for installing without the service menu.
- **lito69**, **tulio150** and **DaniFR3**: car tests and porting files for
  the SEAT and the settings.
- **kamgurgul**, **wasimlhr** and **luka-dev**: the MHI2Q projects whose notes
  led to the connection-loop fix, the player priority, and the open QNX
  toolchain.
- **FFmpeg**: H.264 decoding, statically linked, LGPL v2.1 or later.

## License

GPL-3.0, the same as upstream. See [LICENSE](LICENSE). Release packages
contain files built from this source plus the MIT-licensed items above. They
contain no Volkswagen, Skoda, Harman or Apple program files.

Not affiliated with or endorsed by Volkswagen AG, Skoda Auto, Harman, Google
or Apple. Android Auto and Google Maps are trademarks of Google LLC; CarPlay
and Apple Maps are trademarks of Apple Inc.

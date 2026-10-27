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

| | Upstream | This fork |
|---|---|---|
| Sharper map (`CLUSTERMAP_FULL_FRAME`) | Off: the phone draws into an 800×298 band of its frame | **On**: the phone draws the whole frame at the cockpit's real shape, so more of the picture's pixels reach the cockpit |
| Map size (`GAL_SECONDARY_DPI`) | 125 | **110**: smaller text and a compact turn card |
| Map space (`GAL_SECONDARY_INSETS`) | 40,40,127,127 | **40,127,127,127**: the turn card at the top, centred, clear of the cockpit's top line and its two lower segments |
| Day/night (`GAL_SECONDARY_UI_THEME`) | 2, always night | **0, automatic**: follows the car's light sensor, as on the centre screen |
| Cockpit window (`GAL_PLAYER_WINDOW`) | Taken from the display manager | Also preset to **1010×376**, so a first install fits even before the cockpit has shown its own map |
| Insets above 127 | Often too long for the message, and then none are sent | Sent: the automatic theme is left out of the message so they fit; if they still do not fit, each is cut to 127 and the log says so |
| Green menu | Status, logs, uninstall, arrows switch | **Also** the sharper map on and off, test positions for the turn card, and the map size ([below](#green-menu-switches)) |
| Building | Linux, macOS | **Also Windows**: Git Bash and Docker Desktop |

Packages are named `mib-cluster-map_v1.1.1-betaN-skoda.zip`.

## Install

1. **Make the SD card.** Format a 2 to 32 GB card as FAT32. Download the zip
   from [Releases](../../releases) (or [build it](#building)) and copy
   everything inside it to the card:

   ```text
   (SD card)
   ├── ClusterMap/
   ├── Custom/
   ├── metainfo2.txt
   └── _Swdlautorun.txt
   ```

   Put it in **SD slot 1**, with the other slot empty.
2. **Run the update.** Engine running or a charger connected. Hold **MENU**
   until the service screen appears, then `Software updates/versions` >
   `Update` > the SD card > **`MIB Cluster Map`**. Let it finish (a
   "Version back documentation" screen at the end is normal: press
   `Cancel`), then hold the power button for ten seconds to reboot. An
   autorun file on the card starts the update without the menu (see the
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
writes the card's settings again and so resets the green-menu tests.

The green menu and SSH routes, every setting, and recovery are in the
[Install guide](docs/Install.md).

**Uninstall:** green menu > `ClusterMap` > **Uninstall and restore original
state**, then reboot. Or, without the menu: on a computer, move
`UNINSTALL.txt` from the folder `to uninstall, move this file up one folder`
up into `ClusterMap`, and run the same update again.

## Green menu switches

Each changes only the unit's own copy of the settings and takes effect after a
reboot. The turn card tests are measured for the 1010×376 window at DPI 110.

| Entry | What it does | On the Superb |
|---|---|---|
| Test: sharper map ON / OFF (margins) | The whole frame, or upstream's 800×298 band | ON is a little sharper with a better placed card (beta9); ON is the default |
| Test: hide the turn card (small space) | Leaves Google Maps a space too small for the card, where the car sits. Maps then leaves the card out, and the car stays in the middle | **Works** (beta12): no card, the car centred, the route ahead visible |
| Test: turn card top left / top right | Moves the space Maps puts its card in to one side | Works, but the car and the whole view move with the card (beta12): Maps keeps the card centred above the car |
| Test: turn card at the bottom | The card in a band at the bottom, between the two lower segments | Not tested yet |
| Turn card at the top (standard) | Back to the installed space | |
| Test: map smaller / larger (DPI -10 / +10), Map size as installed | The map, its text and the turn card smaller or larger, between DPI 80 and 170 | Not tested yet |

## Status on the Superb (`P4526`)

| Part | State |
|---|---|
| Install by software update, green menu | Car-tested, beta8 to beta12 |
| Android Auto map, with and without a route | Car-tested |
| Automatic day/night | Car-tested (beta8), also by another owner ([upstream #41](https://github.com/MacsInSpace/mib-cluster-map/issues/41)) |
| Sharper map | Car-tested (beta9) |
| Android Auto version 1.5 (`GAL_DUALSCREEN_AAP_MINOR=5`, from beta11) | Car-tested (beta12): map and insets as before. Earlier tests ran at 7: go back to 7 if something stops working |
| Turn card hidden or moved | See [above](#green-menu-switches) |
| Turn card at the bottom, map size | Not tested yet |
| Turn-arrows jar beside the map (`CLUSTERMAP_KEEP_ARROWS=1`) | Not tested on a Skoda |
| CarPlay map | In the package from upstream, not tested on a Skoda ([CarPlay](docs/CarPlay.md)) |
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
| VW, Audi, CarPlay | The code is upstream's and still knows every unit it supports, but the settings here are tuned for the Skoda. Use [upstream's releases](https://github.com/MacsInSpace/mib-cluster-map/releases) |

You need the Virtual Cockpit for the map. The firmware train is on the green
menu **Status** screen. A unit whose train does not start with `MHI2_ER_`
(MIB2 Standard, for example, starts with `MST2_`) is a different unit and not
covered.

## Building

From Git Bash on Windows with Docker Desktop, or on Linux and macOS:

```bash
RELEASE_VERSION=v1.1.1-beta13-skoda ./build_local.sh
```

The package lands in `dist/` and its contents in `dist/sdcard/`. The digits of
`RELEASE_VERSION` become the version the head unit compares, so count up from
the installed one. The first run builds FFmpeg once. Details are in
[Development](docs/Development.md) and at the top of `build_local.sh`.

## Documentation

| Page | For |
|---|---|
| [Install guide](docs/Install.md) | Install routes, the menu, settings, logs, safety and recovery, getting your unit added |
| [CarPlay](docs/CarPlay.md) | The CarPlay map: design, status, testing |
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
- **harman-f** ([mhi2_altscreen_carplay](https://github.com/harman-f/mhi2_altscreen_carplay))
  and **aberbic** ([Audi MHI2 AltScreen](https://github.com/aberbic/Audi-MHI2-Virtual-Cockpit-Altscreen-CarPlay-AndroidAuto)):
  the open CarPlay cluster work the CarPlay map builds on. harman-f's hook is
  included from source under GPL-3.0.
- **Mr-MIBonk** ([M.I.B.](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)):
  the `Swdlautorun.txt` trigger for installing without the service menu.
- **lito69**, **tulio150** and **DaniFR3**: car tests and porting files for
  the SEAT and the settings.
- **kamgurgul**, **wasimlhr** and **luka-dev**: the MHI2Q projects whose notes
  led to the connection-loop fix, and the open QNX toolchain.
- **FFmpeg**: H.264 decoding, statically linked, LGPL v2.1 or later.

## License

GPL-3.0, the same as upstream. See [LICENSE](LICENSE). Release packages
contain files built from this source plus the MIT-licensed items above. They
contain no Volkswagen, Skoda, Harman or Apple program files.

Not affiliated with or endorsed by Volkswagen AG, Skoda Auto, Harman, Google
or Apple. Android Auto and Google Maps are trademarks of Google LLC; CarPlay
and Apple Maps are trademarks of Apple Inc.

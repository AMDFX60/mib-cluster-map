# Install guide

Three ways in, all running the same installer. Use the first unless you
already work in the toolbox or over SSH.

| Route | Needs | Tested on a car |
|---|---|---|
| 1. Software update from the SD card | Nothing | Pending |
| 2. Green menu screen | The ClusterMap screen, which route 1 adds, or the [MQB Coding MIB2 Toolbox](https://github.com/jilleb/mib2-toolbox) | Pending |
| 3. SSH | The toolbox's SSH service | Yes |

Before you start: park, keep the engine running or a charger connected, and
never switch the ignition off while something is installing. Hours of
ignition-on testing flattened a healthy battery during development. If a
screen does not look like the description, stop and ask in an issue.

**Recommended in any case:** install the toolbox's SSH service
(`Customization` > `Advanced` > **Install SSHD service**,
[guide](https://github.com/jilleb/mib2-toolbox/wiki/SSH-Login)). It is the
way back into the unit if the centre screen ever fails to start.

## The SD card

1. Format a 2 to 32 GB card as FAT32. This erases it.
   - Windows: right-click the card > `Format` > `FAT32`.
   - macOS: Disk Utility > the card's device > `Erase` > `MS-DOS (FAT)`,
     scheme `Master Boot Record`.
2. Copy everything inside the release zip to the card:

   ```text
   (SD card)
   ├── ClusterMap/      installer, programs, settings
   ├── Custom/          the menu screen, for route 2 via the toolbox
   ├── metainfo2.txt    makes the card a software update
   └── Swdlautorun.txt  starts the update by itself when the card goes in (below)
   ```
3. Put it in **SD slot 1**, with slot 2 empty.

## Route 1: software update

1. Hold **MENU** until the service screen appears (several seconds).
2. `Software updates/versions` > `Update` (top right) > the SD card >
   **`MIB Cluster Map`**.
3. Let it run. The unit may restart, then show a list of modules mostly marked
   `N/A` and `ClusterMap` `OK`: press back (top right). A screen headed
   **Version back documentation** ("Start diagnostic tester ... Accepting the
   error code leads to a restart") is normal: press `Cancel`. The unit
   restarts once more.
4. Back at the home screen, hold the power button for ten seconds to reboot.

**Autorun (on by default):** `Swdlautorun.txt`, at the top of the card, makes
units that honour it start this update by themselves when the card goes in
(the trigger M.I.B. uses; a Golf started it straight away, Audi untested).
The update renames the file to `_Swdlautorun.txt` when it finishes, so it
does not start again after the restart; installing on a second car means
renaming it back first. If nothing happens within two minutes, the unit does
not honour it: use the menu above. To keep the card from ever starting on
its own, rename the file to `_Swdlautorun.txt` before inserting it.

What it does, without asking:

- copies the ClusterMap screen to the green menu and switches that menu on;
- checks the firmware and installs **the map** where there is a profile for
  it, otherwise **the turn arrows** where that jar is known to work, otherwise
  **nothing**, and then collects the files needed to add the unit (see
  [Getting your unit added](#getting-your-unit-added));
- with the map: adds the NavActiveIgnore patch if it is missing, and switches
  off the turn-arrows jar if it is loaded (the two cannot run together);
- keeps every original file it changes, on the unit and on the card.

Its report is `ClusterMap/update_result.txt` on the card. A good run ends with
`CLUSTERMAP_INSTALL_OK` (map) or `CLUSTERMAP_TURN_BY_TURN_OK` (arrows).

Two marker files change what the update does. Each ships in a folder whose
name says what to do with it; move the file up into `ClusterMap` itself, run
the update, then move it back:

| Marker | Folder | The update then |
|---|---|---|
| `UNINSTALL.txt` | `to uninstall, move this file up one folder` | removes everything and restores the original state |
| `COLLECT.txt` | `to only check compatibility, move this file up one folder` | installs nothing: writes the status check to `update_result.txt` and collects the porting files. Only the menu screen file is copied to the unit |

## Route 2: green menu

If route 1 has run, the screen is already there. Otherwise add it with the
toolbox: its files and ours on the same card (merge the `Custom` folders and
**keep the toolbox's `metainfo2.txt`**), then green menu > `mqbcoding` >
`Customization` > `GreenMenu` > **Install GreenMenu screens and scripts from
Custom/GreenMenu**. A message about a missing `scripts` folder is harmless.
Leave the green menu and open it again.

Open it with MENU (hold) > `Testmode` > `Green Developer Menu` >
**`ClusterMap`**:

| Entry | What it does |
|---|---|
| 1. Status and compatibility check | Firmware train, verdict, what is installed, Java patches |
| 2. Install cluster map | The same installer as route 1 |
| Uninstall and restore original state | Full revert |
| Turn card hidden (standard), then reboot | Only for a 1010×376 window: no green card. The 160×60 space at 25-45 % of the height (`75,163,320,320`) is too short for it, so Maps leaves it out, draws the car just below the middle and the arrival time in a line at the bottom. Car-tested |
| Turn card top right, then reboot | The same space 25 lines lower (`100,138,320,320`): Maps shows the card in the top right corner with the arrival time under it, and the car lower down. Car-tested |
| Turn card top left, then reboot | As top right but the space moved right (`100,138,480,160`), so the free room is on the left. Maps decides which side its card goes; if it stays right, the car is just further right. Not yet car-tested |
| Test: map smaller / larger (DPI -10 / +10), then reboot | Changes `GAL_SECONDARY_DPI` in the unit's copy in steps of 10, between 80 and 170: smaller draws the map, its text and the turn card smaller. The turn card positions above are measured at DPI 110. The status check shows the value |
| Map size as installed, then reboot | Back to the DPI the install wrote. An install from the card also does that |
| Switch to turn-by-turn arrows instead (no map) | Removes the map, installs the arrows. Install switches back |
| Save logs to SD | For a problem report. Before rebooting: logs are in RAM |
| Collect files for porting (quick) | About 2.5 MB, read only |
| Collect for porting, with Java image (55 MB, slow) | Only for a turn-arrows port |

The status check says `supported: yes (tested firmware)`, `yes (UNTESTED
firmware ...)` (it may work; please report the result) or `NO` (stop; nothing
was changed). Run Install, wait for `CLUSTERMAP_INSTALL_OK`, leave the menu
and reboot. Do not change entries this guide does not mention.

## Route 3: SSH

SD card in slot 1, laptop on the car's wifi hotspot, SSH in as root:

```sh
mount -uw /fs/sda0
sh /fs/sda0/ClusterMap/GEM/install.sh       # or ClusterMap/enable_hook.sh for the map alone
sh /fs/sda0/ClusterMap/GEM/uninstall.sh     # to remove
```

Then reboot. `enable_hook.sh --help` lists its options.

## Use it

Wait about two minutes after the unit starts. Plug in the phone, start a map
on it, and put the cluster in **map view** with the steering wheel buttons.
The phone's map appears within a few seconds and stays when a route starts.
The car's own navigation still works; the cluster shows the phone's map only
while the phone sends it.

## What the installer changes

| Where | What |
|---|---|
| `/mnt/system/etc/eso/production/smartphone_integrator.json` | adds the hook to the Android Auto program's start-up; original kept as `.gal-dualscreen.original` and in `ClusterMap/backups/` on the card |
| `/mnt/app/eso/lib/gal_dualscreen/` | the hook, a helper library, a copy of the settings |
| `/mnt/app/navigation/stream-player` | the video player |
| `/mnt/app/eso/hmi/lsd/lsd.sh` | Java patch lines: NavActiveIgnore added if missing (on the trains above, or anywhere with `CLUSTERMAP_ADD_NAVIGNORE=1`), the turn-arrows jar's line removed (map) or added (arrows). Previous file kept as `lsd.sh.before_<jar>` |
| `/mnt/app/eso/hmi/lsd/jars/NavActiveIgnore.jar` | the patch itself, when the installer adds it. Packages 1.1.3-beta1 to 1.2.2-beta5 had a green-menu test that replaced it with a 30 fps copy (27340 bytes); an install or uninstall puts the 20 fps jar back if that copy is still there |
| `/mnt/app/eso/hmi/engdefs/cluster-map.esd` | the menu screen |

Uninstall puts all of it back and removes the menu screen. Three things stay,
all harmless: the engineering menu stays switched on, the unused backup copies
of the files it edited stay beside them, and any fault the SD update logged
stays (see [Fault B201A00](#fault-b201a00)). Run the status check before the
reboot: it should say the hook is not installed. To use the green menu again
later, run the update with `COLLECT.txt`.

### Fault B201A00

Any software update run from SD can log `B201A00 Check Software Version
Management` in the head unit (5F), even when this package then installs
nothing. One owner's scan shows it, with a sporadic `U10CF00`, at the minute of
the SD update and before anything of this project ran (#10). Uninstalling does
not clear it. It is the head unit reporting a software change; a workshop can
clear it with a diagnostic tool's installation-change confirmation. Whether it
has any other effect is not known.

One owner cleared it themselves in 5F with the adaptation "Confirmation of
installation change", using a key from a third-party tool (#10). We have not
tried that route.

If the update stops on another module, for example "device not responding"
naming the instrument cluster, pressing Skip let the install finish on one car
(#40).

This fork has no CarPlay map. Packages before 1.1.3 installed one where the
unit's CarPlay library fitted: an entry in CarPlay's start-up, its files in
`/mnt/app/eso/lib/gal_dualscreen/`, `/mnt/app/root/mibr-carplay111-safearea.conf`
and a firewall rule marked `# clustermap carplay map` in
`/mnt/system/etc/pf*.conf`. Installing 1.1.3 or later takes all of that out
again, and so does Uninstall. CarPlay itself works as stock.

## Cluster map window

The cluster only shows the head unit's map window at that window's own size:
800×480 on the Golf, 1010×376 on some SEAT and Skoda clusters. A window of
another size arrives as coloured stripes. The installer reads the size from
the display manager (`dmdt gd`, window 33) and opens the player's window at
it. Android Auto's cluster video has a fixed size (1280×720 with this fork's
720p picture, 800×480 with `CLUSTERMAP_720P=0`), so where the window has
another shape the phone is asked to leave margins (270×344 or 0×182 for
1010×376) and the player shows the rest in the window. If the size cannot be
read, the card's `GAL_PLAYER_WINDOW` is used when set (this fork ships
`GAL_PLAYER_WINDOW=1010x376`), then the size the player found on this cockpit
at an earlier start, otherwise the usual size for the make (1010×376 on SEAT
and Skoda, 800×480 on VW and anything else). The install
output and the unit's copy of the settings (`GAL_PLAYER_WINDOW`,
`GAL_SECONDARY_MARGINS`) show what was chosen.

The display manager only lists window 33 once the cockpit has shown it, so
the installer can be left with a guess. The player therefore reads the size
again each time it starts. If it differs, it opens the window at the real size
and corrects the two settings for the next start, and saves the size for the
next install. Until then the picture can have black bars. (Up to 1.3.0 that
correction never ran: its script could not find its own folder, upstream
#95.)

**Upstream's sharper map (not in this fork's menu any more).** The margins cost sharpness: on 1010×376 only 298 of the frame's 480 lines
carry map, enlarged to fill the window. `CLUSTERMAP_FULL_FRAME=1` asks the
phone to draw on the whole frame with non-square pixels instead
(`GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4`, 16117 for 1010×376), and the player
stretches it to the window. On a Skoda P4526 the phone honoured the ratio but,
at the same DPI, showed more map rather than finer map, so the hook now scales
DPI and all four insets by the ratio: the map keeps its scale and the turn card
its place, with about 1.6 times the lines upwards (across stays 800). On the
Skoda that came out a little sharper, with the turn card placed better, and
the fork installed it on from 1.1.1-beta10 to 1.2.2-beta3. The 720p picture
below replaced it; `CLUSTERMAP_FULL_FRAME=1` with `CLUSTERMAP_720P=0` still
works.

**720p picture (this fork's standard, `CLUSTERMAP_720P=1`):** even the sharper map leaves
only 800 columns for the 1010 of the window, and the phone squeezes its picture
before the player stretches it again. Android Auto also offers 1280×720 for a
cluster display: with margins of 270×344 the phone draws exactly the
1010×376 window's pixels into the middle of that frame, and the player shows
them 1:1, without any scaling (other projects run 720p and 1080p cluster
streams; Google's own head unit documentation sets a cluster up this way).
The hook scales DPI and insets from the 800×298 band to the window by
1010/800, so the settings keep their meaning; its log says
`event=config.hd_frame`. The player log says `1:1 (exact pixels)` in its
`render:` line when it works. The margins are black and cost almost nothing,
and from 1.2.2-beta4 only the window's part is copied and uploaded.
Car-tested on the Superb (1.2.2-beta3): sharper than the sharper map, but
only 9 to 10 pictures a second. The player's `timing:` line (once a minute
with its `health:` line, from beta4) showed why: decoding took about 100 ms
a picture in software without NEON, one core full; copying, uploading and
showing took about 13 ms. From beta5 FFmpeg is built with the Tegra 3's NEON
routines (`cpu: NEON present` in the player log). If the cockpit ever shows
no map, set `CLUSTERMAP_720P=0` on the card and install again.

Upstream has the same switch (off by default) but scales the insets
differently: it first takes the band's margins (91 lines top and bottom on
1010×376) off the top and bottom inset. This fork keeps its own rule, because
every inset value it ships was tuned with it on the car; with upstream's rule
the hidden turn card's space would come out much taller and the card would
likely come back. The hook log says `rule=skoda` in its
`event=config.full_frame` line.

## Settings

Edit `ClusterMap/gal_dualscreen.conf` on the card, run the install again so
the unit's copy is refreshed, and reboot. The file documents every key.

**A line that starts with `#` is switched off.** Many settings ship that way.
To use one, delete the `#` at the very start of the line, and keep only one
active line per setting:

```ini
#GAL_PRIMARY_DPI=160    <- off: no effect, whatever the value
GAL_PRIMARY_DPI=160     <- on
```

The same goes for any line you were asked to add, such as `GAL_PROFILE_TRIAL=`:
it must start at the beginning of the line, with no `#` in front.

| Setting | Shipped | Change it when |
|---|---|---|
| `GAL_SECONDARY_DPI` | 110 (this fork: smaller turn card on the Skoda) | map text and turn card too big (lower) or too small (higher). Upstream ships `auto`, which the installer fills in per make (Skoda 125); a number here is kept as it is |
| `GAL_PRIMARY_DPI` | unset (the unit's own) | Android Auto on the **centre screen** looks too large or too small. 60 to 400, the unit's own is usually 213; lower shows more. The same as aawireless's DPI setting, but kept in passthrough mode. Remove the `#` in front of the line. Car-tested upstream (#71), not yet on a Skoda |
| `GAL_SECONDARY_INSETS` | auto (this fork: from `CLUSTERMAP_TURN_CARD` on 1010×376) | map controls or the ETA hide behind the dials or a warning light. Top, bottom, left, right. With theme 0 up to three values may be above 127, with theme 1 or 2 only one; beyond that the smallest ones are cut to 127, one at a time, until the setting fits. See the settings owners have settled on, below |
| `CLUSTERMAP_TURN_CARD` | hidden | where Google Maps shows its turn card on the 1010×376 window: `hidden` (no card, `75,163,320,320`), `top_right` (`100,138,320,320`) or `top_left` (`100,138,480,160`; Maps decides the side, not yet car-tested). The green menu's "Turn card ..." entries switch it in the car; the next install keeps that choice while this line says hidden. Numbers in `GAL_SECONDARY_INSETS` win over it |
$1 unset | you want a custom vertical crop of Android Auto's 800×480 frame instead of the margins. Nonzero values disable the installer's margins but keep its pixel-aspect setting (including `CLUSTERMAP_FULL_FRAME=1`); the player crops those rows and stretches the rest to the full window. From upstream (Audi A3, #85); not tried on a Skoda, where the sharper map does this job |
| `GAL_SECONDARY_UI_THEME` | 0 (automatic) | 0 switches between day and night with the car, as the centre screen does (Waze stays dark); 1 is always light, 2 always dark. 1 or 2 costs two bytes of the insets message, so fewer insets can go above 127 |
| `CLUSTERMAP_KEEP_SETTINGS` | unset (keep) | you want a clean install. Each install remembers the lines you changed in `gal_dualscreen.conf` and puts them back at the next install wherever the new card still has the shipped default; a line changed on the new card wins, and `update_result.txt` lists what was kept. When you install the same release again, a setting you have edited on the card since the last install is used as the card has it. `0` installs only the card's settings. Settings from releases before this mechanism (the fork's 1.1.x) are not carried over. The green-menu tests are not kept: they change only the unit's copy. The uninstall forgets them |
| `CLUSTERMAP_FULL_FRAME` | 0 | upstream's sharper map, only with `CLUSTERMAP_720P=0`: the whole 800×480 frame with wide pixels, see [Cluster map window](#cluster-map-window) |
| `CLUSTERMAP_720P` | 1 (this fork) | 1 asks the phone for a 1280×720 frame with margins that leave exactly the window (270×344 on 1010×376), shown 1:1. Wins over `CLUSTERMAP_FULL_FRAME`. DPI and insets stay set as for the 800×298 band; the hook scales them to the window. Car-tested on the Superb (1.2.2-beta3). 0 goes back to the 800×480 frame with margins |
| `GAL_DUALSCREEN_AAP_MINOR` | 5 | the Android Auto version the unit claims (1.x). The map shows at 2 to 7. At 6 or higher Google Maps sends newer navigation messages this unit cannot read; the hook translates them into the old ones (`GAL_DUALSCREEN_NAV_TRANSLATE`, on), so the arrows jar should keep its turn pictograms; not yet car-tested above 5 (#4). This fork's Skoda settings were car-tested at 7 and again at 5 (beta12, map and insets); go back to 7 if insets, theme or the sharper map stop working |
| `GAL_PLAYER_WINDOW` | 1010x376 (this fork: Skoda) | used only when the installer says the cluster map window was "not reported by the display manager"; otherwise the reported size wins. Set it to your cluster's window if that is not 1010x376 |
| `GAL_VC_CONTEXT` | 70 | the cockpit map is in another display context. 70 on VW, SEAT and Skoda; Audi units differ (the installer sets them by itself) |
| `CLUSTERMAP_KEEP_ARROWS` | 0 | 1 keeps the turn-arrows jar with the map (adds it if missing): map, arrows and music together on SEAT. Leave it at 0 on VW: the map has gone blank when a route starts, and a Golf `P4521` cockpit switched to its own arrow view after a few presses of OK and stayed there until the arrows were removed. One Tiguan `K4525` reports both working (#44). Not tested on a Skoda |
| `CLUSTERMAP_MUSIC_INFO` | 0 | 1 shows the track playing (title, artist, cover) on the cockpit's media screen with the map: a music-only build of the arrows jar that sends no turn data, so the map stays up on a route. Only on trains where the arrows jar is known to work (`P4521`, `K4525`, `P4708`, `P4709`): on the Skoda `P4526` the installer ignores it. Ignored with `CLUSTERMAP_KEEP_ARROWS=1`. Not car-tested yet |
| `CLUSTERMAP_TURN_INFO` | 0 | 1 sends Android Auto's turn info (arrow, distance) to the cockpit with the map: a build of the arrows jar that, unlike `CLUSTERMAP_KEEP_ARROWS=1`, never switches the cockpit to its arrow view, so the cockpit should draw its own arrow beside the map. Includes the track info of `CLUSTERMAP_MUSIC_INFO` and wins if both are set. Same trains (not the Skoda `P4526` yet); ignored with `CLUSTERMAP_KEEP_ARROWS=1`. Tested upstream on a Golf R `P4521`: map kept, arrow in the right dial, road name above the map |
| `CLUSTERMAP_TURN_TEXT` | auto | with `CLUSTERMAP_TURN_INFO=1`, the road name shows twice with the map (the cockpit's line above Google's card). `auto` sends it only while the cockpit shows no map, `always` every time, `never` not at all (arrow and distance only). Not car-tested yet |
| `CLUSTERMAP_ADD_NAVIGNORE` | 0 | the map goes as soon as a route starts, on firmware where the installer does not add `NavActiveIgnore` by itself (on the Skoda `P4526` it does). 1 adds it, with a backup, and uninstall removes it. It edits the script that starts the centre screen, so check SSH works first |
| `GAL_PLAYER_DECODER` | sw | `sw` is the tested software decoder. `hw` uses the unit's own video decoder and frees most of a processor core. If it will not open, the player uses software; if it fails while decoding, it stays off until the next reboot. **Not yet car-tested** |
| `GAL_PLAYER_PRIORITY` | 12 (this fork) | the player's priority, raised to this and never lowered (QNX's default is 10), so the compositor stalls the cockpit map less. 0 or no line leaves it as spawned; at most 20. The player log says `priority: 10 -> 12` |
| `GAL_PLAYER_NVSS_OUTPUT` | 1 | the cluster stays black with `hw`: try 0 (uncomment the line first) |
| `GAL_PLAYER_NEON` | 1 | 0 decodes without NEON: slower, about 10 pictures a second at 720p. NEON leaves out the few routines that access memory misaligned, which this unit's kernel stops with SIGBUS (1.3.0-beta2 crashed in one at every start; tools/ffmpeg_qnx_aligned.sh). Should the player still crash, it decodes without NEON until the next reboot by itself (`cpu: NEON off` in its log) |
| `GAL_SECONDARY_MAX_UNACKED` | 4 (from 1.4.0) | how many cockpit pictures the phone may send before the player has drawn them, 1 to 16. Each one waits in front of the decoder, so this bounds how far the cockpit runs behind the phone: about this many times the decode time (45 ms or so at 720p), 34 to 213 ms on average on the Superb. 3 for a little less delay; 2 cost pictures in a PC test; 8 is the value up to 1.3. The hook log's `ack.latency` line gives the delay once a minute |
| `GAL_PLAYER_COLOR` | auto | `auto` converts colours as the stream says, limited range (16-235) unless it says full. Before 1.2.2-beta3 every stream was taken as full range, which made blacks grey and the map paler. `old` puts that back to compare; the player log line `colour:` says what was chosen |
| `GAL_DUALSCREEN_DEBUG`, `GAL_FIX_STREAM_TIMING`, `GAL_PLAYER_STATS`, `GAL_HOOK_LOG_MAX_MB` | 0, 0, 0, 1 | full trace for a bug report: 0, 1, 1, 10, then install over SSH with `enable_hook.sh --debug` |

### Settings owners have settled on

The dials differ between cars, so these are starting points rather than
recommendations. All are `GAL_SECONDARY_DPI` with `GAL_SECONDARY_INSETS` as
top, bottom, left, right. This fork ships the hidden-card row for the Skoda as
numbers. Upstream ships `auto`, and with `auto` in the file the installer
picks the row marked *auto* for the make; to try another row, put its numbers
in the file. Values that upstream owners tuned with the sharper map on use
upstream's inset rule (see [Cluster map window](#cluster-map-window)), so they
do not carry over one to one.

| Cluster | DPI | Insets | From |
|---|---|---|---|
| SEAT 1010×376 (`P4708`, `P4709`), *auto* | 125 | `105,127,127,127` | SEAT owners, #4 and #19 (140 until beta11; owners found it too large) |
| SEAT, for Waze | 110 | `105,127,127,127` | DaniFR3, #4 |
| VW 12.3 in Passat B8 (`K4525`) | 145 | `56,73,127,127` | d4nt387, #8 |
| VW 12.3 in Tiguan (`K4525`) | 145 | `56,120,127,127` | totocastellano-cmd, #27 |
| Skoda 1010×376 (`P4526`), upstream's *auto* | 125 | `40,127,127,127` | raskrivuska, #15 (the card at the top; the green menu's top test) |
| Skoda 1010×376 (`P4526`), turn card hidden (shipped) | 110 | `75,163,320,320` | this fork, beta12 to 1.2.2-beta3 and from beta5: the car just below the middle, the arrival time at the bottom |
| Skoda 1010×376 (`P4526`), turn card top right | 110 | `100,138,320,320` | this fork, 1.2.2-beta4: the card top right with the arrival time, the car lower |
| Skoda 1010×376 (`P4526`), turn card hidden, car lower | 110 | `134,104,0,0` | this fork, 1.1.2 to 1.2.2-beta1: the car behind the lower bar, out of sight |
| VW 12.3 in, ETA card showing (`K4525`) | 138 | `52,82,127,127` | totocastellano-cmd, #20 and #12 (`53,83,127,127` on a second car: the same within a pixel) |
| VW 12.3 in Passat B8 2019 (`K4525`), ETA card showing, with `GAL_SECONDARY_UI_THEME=0` | 138 | `56,73,127,127` | danielszyszko-ui, #41 |
| VW Golf (`P4521`), ETA card showing, Google Maps and Waze, *auto* for VW | 138 | `52,82,127,127` | tvarszegi1, #8, road-tested |
| VW Passat B8 2018 (`P4512_1`), small and large dials, *auto* for VW | 138 | `52,82,127,127` | slechtaadam-byte, #47 |

Lower DPI makes the map and its text smaller, so more of the map shows; below
about DPI 140 Google Maps changes from two overlay cards to one in the middle.
Google Maps also drops its arrival-time card when the space left to it is too
short, and DPI is the lever: the one setting anyone has shown with the card
visible on a 12.3 in cluster is 138 with a bottom inset of 82 (#20, #27).
Waze picks its own colours and ignores the day setting.

Logs are kept in RAM only (`/tmp/gal_dualscreen.log`, `/tmp/stream-player.log`)
and lost at reboot. **Save logs to SD** copies them, with the system log, to
a new numbered folder in `ClusterMap/run_logs/` each time. Read them before posting: the system log can contain
phone names and Bluetooth addresses.

## If it does not work

| What you see | What to do |
|---|---|
| The car's own map, or "no map" | Check the cluster is in map view. Unplug the phone, wait ten seconds, plug it in |
| A wireless adapter connects, then drops every few seconds | In the adapter's own app: automatic standby **off**, VAG crash fix **off** (that fix is for VAG *Technisat* units, not Harman), adapter firmware up to date (#12, #35) |
| The phone keeps disconnecting | Save logs, uninstall, reboot, open an issue |
| The map appears, then goes blank when a route starts, or the cluster says "navigation on mobile device is active" | `NavActiveIgnore` is not loaded. The installer adds it on `P4521`, `K4525`, `P4512`, US `P3662`, Skoda `P4526`, SEAT `P4709` and the Audi A6/A7 C7.5 `K3663` (the Audi build). On any other firmware set `CLUSTERMAP_ADD_NAVIGNORE=1` and install again, or apply it from the MIB2 Toolbox (**Customization > Navigation > Ignore navigation-active status**). Check SSH works first — see [Safety and recovery](#safety-and-recovery) |
| The map appears, then goes blank when a route starts, with `NavActiveIgnore` loaded | Run the install again: something re-enabled the turn-arrows jar |
| Black cluster with `GAL_PLAYER_DECODER=hw` | `GAL_PLAYER_NVSS_OUTPUT=0`, or back to `sw` |
| The centre screen stays black after a reboot | See below |

## Safety and recovery

What the installer does to avoid a unit that will not start:

- **Wrong firmware is refused** before anything is written, and the hook
  checks again every time Android Auto starts; on a mismatch it does nothing.
- **Only two existing system files are edited**: the smartphone start-up
  configuration and the Java start-up script. Each new version is written to
  a separate file, checked, and only then moved into place. The configuration
  is validated with the unit's own JSON checker, and put back at once if the
  result fails.
- **The turn-arrows jar only goes on firmware where it is known to work.** It
  replaces parts of the unit's interface; on firmware it does not fit, the
  centre screen may not start.
- **Originals are kept**, on the unit and on the card. Nothing in `/lib` or
  `/usr/lib` is touched.

If the centre screen stays black after a reboot, the Java interface did not
start and the green menu is unavailable. Over SSH:

```sh
mount -uw /mnt/app
ls -t /mnt/app/eso/hmi/lsd/lsd.sh.before_*        # newest first
cp /mnt/app/eso/hmi/lsd/lsd.sh.before_<newest> /mnt/app/eso/hmi/lsd/lsd.sh
```

then reboot. If Android Auto itself will not start, the original supervisor
file is `/mnt/system/etc/eso/production/smartphone_integrator.json.gal-dualscreen.original`
(and in `ClusterMap/backups/` on the card). Keep the card until you have
driven with the install for a while.

No software can promise a modified head unit always recovers. These steps
cover the failures seen or foreseen so far.

## Getting your unit added

Each firmware needs a profile, worked out from a few of its files, and an
owner willing to test.

1. Run the update (route 1). On a unit it does not support, it installs
   nothing and copies the files into `ClusterMap/porting_<train>/`, about
   3.2 MB. Or use the `COLLECT` marker, or the green menu's **Collect files
   for porting**.

   It copies the two phone libraries under whatever names the unit carries
   them: the Android Auto receiver (`libautoreceiver.so`, or
   `libautoreceiver_qnx.so.1` on the VWG11 generation). If no known name is there it searches the
   unit and copies what it finds, because a differently named library is the
   usual reason a unit looks unportable when it is not (#28). `info.txt`
   records which names were found.
2. Open an issue with your car, the firmware train, and `info.txt` from that
   folder.
3. **Do not post the other files.** They are Volkswagen and Harman software,
   not ours to distribute; they go to the porter privately.

The folder holds no account data, phone names or VIN. The porter's side is in
[Development](Development.md#adding-a-firmware).

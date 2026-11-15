# Testing 1.4.1 in the car

Package `mib-cluster-map_v1.4.1-beta3-skoda.zip` (Version 14103), branch
`beta-1.4.1`. What it changes against 1.4.0 is in the README's changelog;
this page is the test procedure and how its logs are read.

## Procedure

1. The card in slot 1; the software update starts by itself. Then green menu
   > ClusterMap > **2. Install cluster map**, reboot.
2. Drive, then **Save logs to SD**: the comparison drive, standard settings.
3. For each step: choose it in the green menu (under "Tests 1.4.1"), reboot,
   drive, **Save logs to SD**.

Each step sets the whole test state (a block at the end of the unit's
`gal_dualscreen.conf`, written by `scripts/player_test.sh`), so the order
does not matter. The next install from the card removes it too.

| Step | Settings | What it tests | Look for |
|---|---|---|---|
| (none) | as installed | software decoder with both 1.4.1 speed-ups | per-minute `health:` / `timing:` against 1.4.0 and beta1 |
| 1 | `GAL_PLAYER_RECORD=120` | the same, and the first 2 minutes of the cockpit stream saved | `clustermap-stream.h264` in the log folder; start the route at once |
| 2 | `GAL_PLAYER_DECODER=hw` | the unit's own video decoder, rectangle as left/top/right/bottom | `hwdecode:` lines, `health: hardware decoder` line, what the cockpit showed |
| 3 | `hw`, `GAL_PLAYER_NVSS_RECT=xywh` | the same, rectangle as x/y/width/height | for a map squeezed with black at the right and bottom in step 2 |
| 4 | `hw`, `GAL_PLAYER_NVSS_OUTPUT=0` | the same, output device 0 | for a black cockpit in step 2 |
| 5 | `GAL_SECONDARY_MAX_UNACKED=3` | software decoder, 3 pictures in flight instead of 4 | `ack.latency` lower, pictures a second not lower |
| 6 | none | back to standard | (nothing to save) |

## Reading the logs

Each "Save logs to SD" is a new folder `ClusterMap/run_logs/N` with
`test_step.txt` (the step then active), `unit_gal_dualscreen.conf`,
`stream-player.log`, `gal_dualscreen.log`, `sloginfo.txt` and, after step 1,
`clustermap-stream.h264`. Several saves in one boot repeat the same log,
growing; the last is the fullest.

For every folder:

- **Which build and step:** `test_step.txt`; `event=init build=` in
  `gal_dualscreen.log` must say `v1.4.1-beta3-skoda`.
- **Ran cleanly:** one `stream-player spawn` per boot, `cpu: NEON present`
  and no `NEON off`, no `SIGBUS` / signal 10 in `sloginfo.txt`; the `acks:`
  line's drawn count equals the decoded count.
- **Speed, per minute:** `health:` (pictures a second, brightness, data
  kB/s and kB a picture: new in beta2), `timing:` (decode ms a picture),
  `ack.latency` in the hook log (delay to the cockpit). Compare minutes with
  similar brightness and kB a picture; the map's content moves the decode
  time more than the speed-ups do.

Earlier drives to compare with (decode ms a picture / pictures a second /
`ack.latency` average per minute):

| Drive | Minutes |
|---|---|
| 1.4.0 (beta2 code), `run_logs/1` | 17.7 / 29.6 / 34 (brightness 65), 36.0 / 23.3 / 102, 44.6 / 20.5 / 146, 58.0 / 17.0 / 213 (brightness 209) |
| 1.4.1-beta1, `run_logs_1.4.1beta1/3` | 43.1 / 21.6 / 141 (71), 53.4 / 18.5 / 196 (72), 56.1 / 17.6 / 205 (211), 53.0 / 18.6 / 192 (206) |

The PC expects beta2 and later to decode 7 % (day map) to 14 % (night map)
faster than 1.4.0.

- **Step 1's stream:** the phone's real pictures. Copy it into the
  `streams` folder of the docker volume `mib-cluster-map-neontest` (or add it
  to `tests/neon/inner.sh`'s list) and run `tests/neon/run.sh all`: the
  pictures must equal FFmpeg's C code without a fault, and `prof` gives the
  instructions a picture on real content. `ffprobe` on it gives the profile
  and entropy coding (CAVLC or CABAC), which decides where further speed-ups
  pay.
- **Steps 2 to 4:** `hwdecode: NvSS decoder ready ... picture 135,172
  1010x376 ... rect ltrb|xywh` means it opened; `hwdecode: ... using
  software decode` means it fell back (the line says why);
  `hwdecode: switched off for this boot` means it failed while decoding. The
  `health: hardware decoder` line gives pictures a second and the player's
  processor time. Ask what the cockpit showed (right, squeezed, black, the
  car's own map) and whether the centre screen behaved.

## Decisions after the test

- Hardware decoder right in step 2, 3 or 4 and the centre screen fine:
  make that variant the standard (`GAL_PLAYER_DECODER=hw` and its rectangle
  or output in `config/gal_dualscreen.conf`), test once more, release.
- Otherwise: 1.4.1 with the software speed-ups; the hardware decoder stays a
  documented test switch.
- Step 5 lower `ack.latency` with the same pictures a second: 3 becomes the
  standard window.
- Then 1.4.1 as a release: one consolidated changelog entry, version
  `v1.4.1-skoda`, merged into `main`.

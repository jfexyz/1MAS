# Verified on hardware

What has been checked against real headphones, as opposed to taken from the public sources. Add a
section per model and firmware.

## SonoFlow (HC905), firmware 1.0.5 — 2026-11-21

macOS 27.2 on Apple Silicon, headphones connected to the Mac and playing audio, no phone connected.

**SDP records** (`unomas sdp --refresh`):

| Name           | RFCOMM | Service class                          |
| -------------- | ------ | -------------------------------------- |
| Advanced Audio | —      | `0x110F`, `0x110E` (AVRCP)             |
| OTA1           | 13     | `66666666-6666-6666-6666-666666666666` |
| (unnamed)      | 2      | `0x1203`, `0x111E` (Hands-Free)        |
| (unnamed)      | —      | `0x110C`, `0x110B` (AVRCP, A2DP sink)  |
| Spp1           | 18     | `0x1101` (Serial Port)                 |

`IOBluetoothDevice.getServiceRecord(for: 0x1101)` returns **OTA1**, not Spp1. Select the channel by
matching the service class, and never open OTA1.

**Opening the channel.** `openRFCOMMChannelAsync` succeeds once the main run loop has turned for
about a second first. Without that warm-up the async open never completes, and
`openRFCOMMChannelSync` fails with `0xE00002BC` (kIOReturnError) after about 3 s. The cause is not
known. The connection worked while the Mac was playing music through the headphones.

**Framing.** Exactly as in the README: requests `11 01`, replies `01 01`, sequence echoed, header
XOR valid on every reply seen.

**Commands:**

| Command         | Sent                            | Reply payload                   | Meaning                                          |
| --------------- | ------------------------------- | ------------------------------- | ------------------------------------------------ |
| Handshake `4D`  | `11 01 00 4D 00 01 00 00 5C 01` | `01`                            | Success. **Not required**: reads work without it |
| Info `4E`       | `11 01 00 4E 00 00 00 01 5F`    | `00 01 00 05 46 00 00 00 00 00` | Firmware 1.0.5, battery 70% (left fields)        |
| Listen `5F`     | `11 01 00 5F 00 00 00 02 4D`    | `01`                            | Strong ANC                                       |
| EQ preset `6A`  | `11 01 00 6A 00 00 00 03 79`    | `00`                            | Preset 0 (Studio)                                |
| Set listen `5E` | payload `03`, `00`, `01`        | `01`                            | Success; audible switch at once                  |

**Listen modes.** `0` off, `1` ANC, and `3` transparency all work, and read back correctly 0.3 s
after the write.

**Notifications.** On a mode change the headphones push an unsolicited `5F` frame carrying the new
mode, which arrives _before_ the write's own reply. The app can rely on these to stay in sync with
changes made from the headphones' button or another device. Not yet tested: whether the button
itself triggers one.

**EQ presets** (2026-11-21). `69 0A` (Pop) replied `01`, `6A` then read `0A`; `69 00` put Studio
back the same way. No unsolicited `6A` was seen after either write, so the app reads the preset back
rather than waiting for a push.

The vendor's iPhone app lists twelve presets for the SonoFlow: Studio, Bass reducer, Bass booster,
Acoustic, Classical, Podcast, Deep, Electronic, Hip-Hop, Lounge, Pop, and Vocal booster. That is
PairFree's list for this model, in ID order, with `0B` named Vocal booster rather than Loud. The
order is assumed to match the IDs; only `00` and `0A` were checked against a read.

**Custom EQ read** (2026-11-21). `54`, sent as the vendor app does with the ten band frequencies as
its payload (two bytes each, high first:
`00 64 00 E5 02 AA 04 D0 0A 0A 0C 23 12 21 1A 5D 25 4E 38 A4`), replied with ten 7-byte records: a
flag, then gain, frequency, and Q, two bytes each.

| Hz    | 100 | 229 | 682 | 1232 | 2570 | 3107 | 4641 | 6749 | 9550 | 14500 |
| ----- | --- | --- | --- | ---- | ---- | ---- | ---- | ---- | ---- | ----- |
| Q/100 | 80  | 80  | 80  | 90   | 140  | 140  | 150  | 180  | 110  | 60    |

- The frequencies and Qs match PairFree's SonoFlow entry.
- Every band's raw gain was `04 B0` (1200), which is 0 dB on PairFree's scale. This curve had never
  been edited. 1MORE Life's per-band offsets (PairFree's `offsets`, such as −800 on the first band)
  did not show up in it, so how they apply is still open.
- The flag was `01` on the first nine records and `02` on the last.

**Dual device connection** (2026-11-21). PairFree's model data says the SonoFlow lacks it, but the
vendor's iPhone app offers it and the headphones answer `77`: `00` while off, `01` after the phone
app turned it on. Changing it **restarts the headphones**, from either app:

| Time  | Event                                                              |
| ----- | ------------------------------------------------------------------ |
| 0 s   | `76 00` sent (`11 01 00 76 00 01 00 01 66 00`); reply `01` at once |
| ~3 s  | the headphones drop off Bluetooth                                  |
| ~11 s | they are connected to the Mac again; `77` reads `00`               |
| 0 s   | `76 01` sent; reply `01`, the same sequence                        |
| ~12 s | connected again; `77` reads `01`                                   |

The setting survives the restart, and turning it on left the other settings (listen mode, EQ preset,
connection mode `6C` = `00`) as they were. Once the phone app was closed, the Mac opened the control
channel as usual.

Turning it off from the menu bar app worked end to end: the confirmation, the restart, and the app's
own reconnection, after which the menu showed it off.

**Not yet tested:** custom EQ writes (`53`), connection mode writes (`6B`), and using the control
channel while the phone app is open.

# Verified on hardware

What has been checked against real headphones, as opposed to taken from the public sources. Add a
section per model and firmware.

## SonoFlow (HC905), firmware 1.0.5 — 2026-11-21

macOS 27.2 on Apple Silicon, headphones connected to the Mac and playing audio, no phone connected.

**SDP records** (`onemore sdp --refresh`):

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

**Not yet tested:** EQ writes (`69`, `53`/`54`), dual device (`76`/`77`), connection mode
(`6B`/`6C`), and behaviour with a phone also connected.

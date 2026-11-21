# 1more-mac

A macOS controller for 1MORE headphones: noise control (off / ANC / transparency), EQ presets, and
battery. Built first for the SonoFlow (HC905); other 1MORE models share the protocol and are planned
through a per-model capability table.

Status: works on a SonoFlow (firmware 1.0.5). A menu bar app shows battery, model, and firmware,
switches between off, noise cancellation, and transparency, chooses the EQ preset, and turns dual
device connection on or off (which restarts the headphones); the `onemore` command-line tool does
the same for probing. `docs/HARDWARE.md` records what has been verified on hardware.

Requires macOS 14 (Sonoma) or later; so far tested only on macOS 27.

## Layout

| Path                       | What it is                                                                                                                                           |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Sources/OneMoreKit`       | The protocol: framing, commands, decoders, the model table, and `Session` (request/response and device state over any byte transport). No Bluetooth. |
| `Sources/OneMoreBluetooth` | IOBluetooth: finding devices and their serial channel, `RFCOMMTransport`, and `HeadphoneConnection`, which connects and reconnects automatically.    |
| `Sources/OneMoreMac`       | The menu bar app, in AppKit (`NSStatusItem` and `NSMenu`).                                                                                           |
| `Sources/onemore`          | `onemore`, a CLI for probing the headphones.                                                                                                         |
| `Support/OneMoreMac`       | The app's `Info.plist` and icon.                                                                                                                     |
| `scripts/build-app.sh`     | Builds and signs `build/1more-mac.app`.                                                                                                              |
| `scripts/make-icon.swift`  | Writes the app icon, `AppIcon.icon`, for Icon Composer. Its header says how to run it.                                                               |
| `Tests/OneMoreKitTests`    | Unit tests, pinned to real packets from the public sources and the hardware.                                                                         |

## Building and running

```sh
swift build
swift test
scripts/build-app.sh && open build/1more-mac.app
$(swift build --show-bin-path)/onemore --help
```

`scripts/build-app.sh` needs Xcode, not only the Command Line Tools, for `actool` to compile the app
icon. The app is a menu bar item only (no Dock icon). The icon is the headphones with a letter for
the current mode: **A** for active noise cancellation, **T** for transparency, **O** for off. It is
dimmed when no headphones are connected. Its menu has a Launch at Login toggle, which registers the
app where it is, so move it to `/Applications` first if you want that. On first launch macOS asks
for Bluetooth permission. The app is ad-hoc signed by default, so a rebuild may ask again;
`SIGN_IDENTITY` in `scripts/build-app.sh` avoids that.

**Only one program can hold the headphones' control channel.** While the app is connected, the
`onemore` CLI and the vendor app on a phone cannot reach the headphones. Quit the app to use them.

`onemore` embeds an `Info.plist` with a Bluetooth usage description (see `Package.swift`), so macOS
can ask for Bluetooth permission. The permission is granted to the app that launches it, normally
your terminal.

Commands: `devices`, `sdp [--refresh]`, `probe`, `mode off|anc|transparent`, `raw <cmd> [payload]`,
and `listen <seconds>`. Add `-v` to log every byte sent and received, and `--no-handshake` to skip
the `4D` handshake the vendor app sends first (the SonoFlow does not need it).

## Protocol

Bluetooth Classic RFCOMM, on the record whose service class is Serial Port (`0x1101`); on the
SonoFlow that record is named `Spp1`. Frames are big-endian:

```
head(2) | command(2) | length(2) | sequence(2) | xor of the 8 header bytes(1) | payload
```

Requests start `11 01`, replies `01`. `Sources/OneMoreKit/Command.swift` lists the commands.

**Safety.** The SonoFlow also exposes an `OTA1` firmware-update service over RFCOMM. Nothing here
opens a record whose name contains `OTA`, and `OneMoreKit` refuses the firmware-update and "delete
music" commands (`49`, `4F`, `71`–`73`) whatever the caller asks. Note that IOBluetooth's own
`getServiceRecord(for: 0x1101)` returns the `OTA1` record on this device, which is why
`DeviceDirectory` matches the service class itself.

### Sources

- [PairFree](https://github.com/Omega-Destroyer/PairFree), `docs/1more/PROTOCOL.md`: the full
  command set and per-model data, from decompiled vendor apps (GPLv3; facts only are used here).
- [aero-q32-console](https://github.com/FOnana/aero-q32-console): the same framing, observed on the
  wire with an AERO Q32 (MIT).
- [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/4637): hard-coded SonoFlow
  packets, tested on hardware. Its "unknown checksum" bytes are the sequence number and header XOR
  above; the unit tests check every one of them.

## Later

- **Firmware updates.** Newer SonoFlow firmware than 1.0.5 exists, but the vendor app fails to
  download it. Updating would need the firmware's download location and the update protocol on the
  `OTA1` channel, both unknown, and a failed update can brick the headphones. Until then the OTA
  guards stay.
- **Custom EQ.** The 10-band curve (`54` read, `53` write; ±3 dB per band) reads correctly on the
  SonoFlow, but writing it, and the menu's Custom preset, need an editor window first.
- **More models**, added to `ModelInfo.known` as each is verified.

## License

MIT. See `LICENSE`.

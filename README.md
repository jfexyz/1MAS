# 1more-mac

A macOS controller for 1MORE headphones: noise control (off / ANC / transparency), battery, and
later EQ. Built first for the SonoFlow (HC905); other 1MORE models share the protocol and are
planned through a per-model capability table.

Status: **phase 0**, proving the protocol on real hardware with a command-line tool. A menu bar app
follows.

## Layout

| Path                    | What it is                                                                         |
| ----------------------- | ---------------------------------------------------------------------------------- |
| `Sources/OneMoreKit`    | The protocol: frame encoding and stream parsing, commands, decoders. No Bluetooth. |
| `Sources/onemore`       | `onemore`, a CLI that talks to the headphones over RFCOMM through IOBluetooth.     |
| `Tests/OneMoreKitTests` | Unit tests, pinned to real packets from the public sources below.                  |

## Building and running

```sh
swift build
swift test
$(swift build --show-bin-path)/onemore --help
```

`onemore` embeds an `Info.plist` with a Bluetooth usage description (see `Package.swift`), so macOS
can ask for Bluetooth permission. The permission is granted to the app that launches it, normally
your terminal.

Commands: `devices`, `sdp [--refresh]`, `probe`, `mode off|anc|transparent`, `raw <cmd> [payload]`,
and `listen <seconds>`. Add `-v` to log every byte sent and received.

## Protocol

Bluetooth Classic RFCOMM, on the record whose service class is Serial Port (`0x1101`); on the
SonoFlow that record is named `Spp1`. Frames are big-endian:

```
head(2) | command(2) | length(2) | sequence(2) | xor of the 8 header bytes(1) | payload
```

Requests start `11 01`, replies `01`. `Sources/OneMoreKit/Command.swift` lists the commands.

**Safety.** The SonoFlow also exposes an `OTA1` firmware-update service over RFCOMM. The CLI never
opens a record whose name contains `OTA`, and `OneMoreKit` refuses the firmware-update and "delete
music" commands (`49`, `4F`, `71`–`73`) whatever the caller asks. Note that IOBluetooth's own
`getServiceRecord(for: 0x1101)` returns the `OTA1` record on this device, which is why the CLI
matches the service class itself.

### Sources

- [PairFree](https://github.com/Omega-Destroyer/PairFree), `docs/1more/PROTOCOL.md`: the full
  command set and per-model data, from decompiled vendor apps (GPLv3; facts only are used here).
- [aero-q32-console](https://github.com/FOnana/aero-q32-console): the same framing, observed on the
  wire with an AERO Q32 (MIT).
- [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/4637): hard-coded SonoFlow
  packets, tested on hardware. Its "unknown checksum" bytes are the sequence number and header XOR
  above; the unit tests check every one of them.

## License

MIT. See `LICENSE`.

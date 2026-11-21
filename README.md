# 1MAS

A macOS controller for various [1MORE headphones](https://usa.1more.com).

The menu bar app displays current battery charge, lists model and firmware numbers, switches between
noise control modes (off/active noise cancellation/transparency), chooses equalizer presets, and
enables/disables dual device connection. The `unomas` command-line tool does the same for probing.

**This app is not affiliated with nor endorsed by 1MORE.**

Built first for the original SonoFlow (model HC905); other 1MORE models share the protocol and are
planned (and might already work... pull requests are welcome). [Models](#models) lists them and what
each one can do. `docs/HARDWARE.md` records what has been verified on actual hardware.

Status: working and testing with the original SonoFlow (model HC905) on firmware v1.0.5.

Requires macOS 14 (Sonoma) or later; so far tested only on macOS 27.

## Layout

| Path                          | What it is                                                                                                                                           |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Sources/UnoMasKit`           | The protocol: framing, commands, decoders, the model table, and `Session` (request/response and device state over any byte transport). No Bluetooth. |
| `Sources/UnoMasBluetooth`     | IOBluetooth: finding devices and their serial channel, `RFCOMMTransport`, and `HeadphoneConnection`, which connects and reconnects automatically.    |
| `Sources/UnoMasApp`           | The menu bar app, in AppKit (`NSStatusItem` and `NSMenu`).                                                                                           |
| `Sources/unomas`              | `unomas`, a CLI for probing the headphones.                                                                                                          |
| `Support/UnoMasApp`           | The app's `Info.plist` and icon.                                                                                                                     |
| `scripts/build-app.sh`        | Builds and signs `build/1MAS.app`.                                                                                                                   |
| `scripts/make-icon.swift`     | Writes the app icon, `AppIcon.icon`, for Icon Composer. Its header says how to run it.                                                               |
| `scripts/import-models.swift` | Writes the model table, `Sources/UnoMasKit/ModelTable.swift`, from PairFree's model data. Its header says how to run it.                             |
| `Tests/UnoMasKitTests`        | Unit tests, pinned to real packets from the public sources and the hardware.                                                                         |

## Installing

There is no download yet. An app from the internet has to be signed and notarized with a paid Apple
Developer account, or macOS refuses to open it. Building it yourself takes a few minutes, and macOS
opens an app built on the same Mac without complaint.

**You need:**

- A Mac running macOS 14 (Sonoma) or later.
- [Xcode](https://apps.apple.com/app/xcode/id497799835), free from the Mac App Store. Open it once
  after installing, so it can finish setting up. Xcode 26 or later, which needs macOS 15.6, also
  builds the app icon; with an older Xcode the app builds with the generic app icon.
- The headphones paired with the Mac in System Settings → Bluetooth.

**Build and install:**

```sh
git clone https://github.com/jfexyz/1MAS.git
cd 1MAS
scripts/build-app.sh
mv build/1MAS.app /Applications/
open /Applications/1MAS.app
```

If the build warns that it could not compile the app icon although Xcode 26 or later is installed,
or fails because no developer tools were found, the terminal is using the Command Line Tools instead
of Xcode. Point it at Xcode, then build again:

```sh
sudo xcode-select --switch /Applications/Xcode.app
```

**First launch:** macOS asks for Bluetooth permission; allow it. The app then appears in the menu
bar, not the Dock. To start it whenever you log in, turn on Launch at Login in its menu.

**Updating:** quit the app from its menu, then:

```sh
cd 1MAS
git pull
scripts/build-app.sh
rm -rf /Applications/1MAS.app && mv build/1MAS.app /Applications/
open /Applications/1MAS.app
```

macOS may ask for Bluetooth permission again after an update, since each build is signed afresh (see
`SIGN_IDENTITY` below).

## Using it

The menu bar icon is the headphones with a letter for the current mode: **A** for active noise
cancellation, **T** for transparency, **O** for off. It is dimmed when no headphones are connected.
With Color Icon on Low Battery turned on in the menu, it turns orange at 20% battery or below. The
menu shows the battery, switches noise control and the EQ preset, turns dual device connection on or
off, and shows the model and firmware.

Being connected is not the same as playing the Mac's sound: with dual device connection on, the
headphones can be connected while the sound comes from the phone or the Mac's speakers. **Use for
macOS Sound Output** is checked while the headphones are the Mac's sound output; choosing it makes
them the output (not the microphone, which would lower the sound quality). It is greyed out while
they have no audio connection to the Mac.

**Only one program can hold the headphones' control channel.** While the app is connected, the
vendor's phone app and the `unomas` CLI cannot reach the headphones; quit the app to use them. If
the app shows "Another app might have control", close the phone app.

## Models

1MAS recognises each model below by its Bluetooth name, as 1MORE's apps do, and offers the controls
that model has. Any other device whose name starts with "1MORE", such as a model newer than this
list, gets the battery, the firmware, and off/noise cancellation/transparency if it answers for
them. A control the headphones do not answer is left out of the menu.

Only the SonoFlow has been tried on real headphones. What the others can do comes from
[PairFree's model data](https://github.com/Omega-Destroyer/PairFree/blob/main/data/1more/devices.json),
which PairFree took from 1MORE's own product list and decompiled apps, not from hardware.
`scripts/import-models.swift` turns it into the app's model table. With an untested model connected,
the menu shows **Help Us Support This Model…**, which opens a device support issue in the browser,
already filled in with the model, firmware, versions, and what the headphones answered. Saying
whether it works, or what does not, is very welcome.

- ✅ Works in 1MAS, verified on the hardware.
- ○ The model has it, and 1MAS offers it, untested. Custom EQ is not offered yet on any model.
- — The model does not have it.

Noise control lists the modes besides off. EQ presets gives the number of presets. The S22Ultra and
S52 are controlled through Tuya's platform rather than this protocol, so 1MAS cannot reach them.

| Model              | Number        | Type       | Noise control                                                                                | EQ presets | Custom EQ | Dual device | 1MAS                      |
| ------------------ | ------------- | ---------- | -------------------------------------------------------------------------------------------- | ---------- | --------- | ----------- | ------------------------- |
| G50                | G50           | Headphones | —                                                                                            | ○ 6        | ○         | ○           | Untested                  |
| HQ20               | HQ20          | Headphones | —                                                                                            | ○ 6        | ○         | ○           | Untested                  |
| HQ31               | HQ31          | Headphones | ○ ANC, transparency                                                                          | ○ 12       | ○         | ○           | Untested                  |
| HQ36               | HQ36          | Headphones | ○ ANC, transparency                                                                          | ○ 6        | ○         | ○           | Untested                  |
| HQ51               | HQ51          | Headphones | ○ ANC, transparency                                                                          | ○ 12       | ○         | ○           | Untested                  |
| HQ60               | HQ60          | Headphones | ○ ANC, transparency                                                                          | ○ 12       | ○         | ○           | Untested                  |
| NANO               | S200          | Headphones | —                                                                                            | ○ 6        | —         | ○           | Untested                  |
| SonoFlow           | HC905         | Headphones | ✅ ANC, transparency                                                                         | ✅ 12      | ○         | ✅          | Verified (firmware 1.0.5) |
| SonoFlow QC30      | SonoFlow QC30 | Headphones | ○ ANC, transparency                                                                          | ○ 12       | ○         | ○           | Untested                  |
| SonoFlow S         | HC905S        | Headphones | ○ ANC, transparency                                                                          | ○ 12       | ○         | ○           | Untested                  |
| SonoFlow SE        | HC306         | Headphones | ○ ANC, transparency                                                                          | ○ 12       | ○         | ○           | Untested                  |
| AERO Q32           | AERO Q32      | Earbuds    | ○ ANC, transparency                                                                          | ○ 6        | —         | ○           | Untested                  |
| Aero               | ES903         | Earbuds    | ○ adaptive ANC, ANC, mild ANC, wind reduction, transparency, pass-through                    | ○ 12       | ○         | ○           | Untested                  |
| ColorBuds 2        | ES602         | Earbuds    | ○ ANC, transparency                                                                          | ○ 22       | —         | —           | Untested                  |
| ComfoBuds 2        | ES303         | Earbuds    | —                                                                                            | ○ 12       | ○         | —           | Untested                  |
| ComfoBuds Mini     | ES603         | Earbuds    | ○ ANC, mild ANC, wind reduction, transparency                                                | —          | —         | —           | Untested                  |
| ComfoBuds Pro      | ES901         | Earbuds    | ○ ANC, mild ANC, wind reduction, transparency                                                | ○ 22       | —         | —           | Untested                  |
| EVO                | EH902         | Earbuds    | ○ adaptive ANC, ANC, mild ANC, wind reduction, transparency, pass-through, voice enhancement | ○ 12       | ○         | ○           | Untested                  |
| Fit                | EF906         | Earbuds    | —                                                                                            | ○ 12       | —         | ○           | Untested                  |
| Fit SE             | EF606         | Earbuds    | —                                                                                            | —          | ○         | —           | Untested                  |
| PistonBuds PRO Q30 | EC305         | Earbuds    | ○ adaptive ANC, ANC, mild ANC, wind reduction, transparency                                  | ○ 12       | ○         | ○           | Untested                  |
| PistonBuds Pro     | EC302         | Earbuds    | ○ ANC, wind reduction, transparency                                                          | ○ 12       | ○         | —           | Untested                  |
| Q12                | Q12           | Earbuds    | —                                                                                            | ○ 6        | ○         | ○           | Untested                  |
| Q21                | Q21           | Earbuds    | ○ ANC, transparency                                                                          | ○ 6        | —         | ○           | Untested                  |
| Q22                | Q22           | Earbuds    | ○ ANC, transparency                                                                          | ○ 12       | —         | ○           | Untested                  |
| Q50                | Q50           | Earbuds    | ○ ANC, mild ANC, wind reduction, transparency                                                | ○ 6        | —         | ○           | Untested                  |
| S-31               | S-31          | Earbuds    | —                                                                                            | ○ 4        | —         | —           | Untested                  |
| S10AI              | S10AI         | Earbuds    | —                                                                                            | ○ 6        | —         | —           | Untested                  |
| S10S               | S10S          | Earbuds    | —                                                                                            | ○ 6        | —         | —           | Untested                  |
| S11                | S11           | Earbuds    | —                                                                                            | ○ 6        | —         | —           | Untested                  |
| S12                | S12           | Earbuds    | —                                                                                            | ○ 6        | —         | —           | Untested                  |
| S15                | S15           | Earbuds    | —                                                                                            | ○ 12       | ○         | ○           | Untested                  |
| S20                | S20           | Earbuds    | —                                                                                            | ○ 6        | —         | —           | Untested                  |
| S20NOVA            | S20NOVA       | Earbuds    | —                                                                                            | ○ 6        | —         | ○           | Untested                  |
| S20PRO             | S20PRO        | Earbuds    | —                                                                                            | ○ 6        | —         | ○           | Untested                  |
| S20Ultra           | S20Ultra      | Earbuds    | —                                                                                            | ○ 6        | —         | ○           | Untested                  |
| S21                | S21           | Earbuds    | —                                                                                            | ○ 6        | —         | ○           | Untested                  |
| S21Air             | S21Air        | Earbuds    | —                                                                                            | ○ 12       | —         | ○           | Untested                  |
| S22                | S22           | Earbuds    | —                                                                                            | ○ 6        | —         | ○           | Untested                  |
| S22Ultra           | S22Ultra      | Earbuds    | —                                                                                            | —          | —         | —           | Not possible (Tuya)       |
| S25                | S25           | Earbuds    | —                                                                                            | ○ 6        | —         | ○           | Untested                  |
| S31                | S31           | Earbuds    | —                                                                                            | ○ 12       | —         | —           | Untested                  |
| S32                | S32           | Earbuds    | —                                                                                            | ○ 12       | —         | —           | Untested                  |
| S51                | S51           | Earbuds    | —                                                                                            | ○ 6        | —         | ○           | Untested                  |
| S52                | S52           | Earbuds    | —                                                                                            | —          | —         | —           | Not possible (Tuya)       |
| S70                | S70           | Earbuds    | —                                                                                            | ○ 6        | —         | ○           | Untested                  |
| S90                | S90           | Earbuds    | ○ adaptive ANC, ANC, mild ANC, wind reduction, transparency, pass-through, voice enhancement | ○ 12       | —         | ○           | Untested                  |
| Z30                | Z30           | Earbuds    | —                                                                                            | —          | —         | —           | Untested                  |

## Development

```sh
swift build
swift test
scripts/build-app.sh && open build/1MAS.app
$(swift build --show-bin-path)/unomas --help
```

`scripts/build-app.sh` signs the app ad hoc, which gives every build a new code identity, so macOS
may ask for Bluetooth permission again after a rebuild. Signing with a stable identity avoids that:
`SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh`.

`unomas` embeds an `Info.plist` with a Bluetooth usage description (see `Package.swift`), so macOS
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

Requests start `11 01`, replies `01`. `Sources/UnoMasKit/Command.swift` lists the commands.

**Safety.** The SonoFlow also exposes an `OTA1` firmware-update service over RFCOMM. Nothing here
opens a record whose name contains `OTA`, and `UnoMasKit` refuses the firmware-update and "delete
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
- **More verified models.** Each one confirmed working gets `verified` in
  `scripts/import-models.swift` and its evidence in `docs/HARDWARE.md`.
- **Low-battery notification**, say at 20% and 10%. The battery is already read every five minutes.
- **A global shortcut to cycle noise control.** Carbon's `RegisterEventHotKey` needs no
  Accessibility permission.
- **Release Control.** A menu item that lets go of the control channel for a while, so the vendor's
  phone app can connect without quitting this one.
- **About and version** in the menu, for bug reports.
- **Continuous integration.** Build and run the tests on every push.

## License

MIT. See `LICENSE`.

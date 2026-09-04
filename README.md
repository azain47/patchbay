# patchbay

A native, open-source DSP rack for macOS system audio. No virtual audio driver.

![patchbay menu bar popover](screenshot.png)

## What it does

- **DSP rack**: reorderable effects chain applied to all system audio
  - Preamp (-24 to +12 dB)
  - 5-band parametric EQ (bell, shelf, low/high pass; frequency, gain, Q per band)
  - Balance
  - Soft-knee limiter with adjustable ceiling
- **Per-device settings**: each output device remembers its own chain
- **Output switching**: one-click default output selection from the menu bar
- **eqMac recovery**: fix stuck audio, restart eqMac, reset CoreAudio

## How it works

patchbay uses the Core Audio process-tap API (macOS 14.2+) instead of installing
a virtual audio driver:

```text
system audio → global process tap → preamp → EQ → balance → limiter → output device
```

The tap and the current output device are combined into a private aggregate
device. An IO proc on that aggregate reads the tapped mix, runs the rack, and
writes the result to the hardware. Nothing is installed into the system.

Two safety properties fall out of this design:

- **Capture is proven before muting.** The tap starts unmuted and silent-output;
  only after real samples arrive and the output layout is confirmed does the
  engine rebuild with a muted tap. A denied permission or unsupported device can
  never silence the Mac.
- **Crashes cannot strand audio.** If patchbay dies, coreaudiod destroys the
  private tap and aggregate automatically and the real device remains the
  default output. There is no driver left behind to hijack routing (the exact
  eqMac failure this project began as a fix for).

The realtime render path is allocation-free and lock-free: the UI publishes
immutable config snapshots through an atomic pointer (`DSPConfig.c`), and the
HAL thread reads whichever snapshot is current.

## Build

Requires macOS 15+ (Apple Silicon) and the Xcode Command Line Tools.

```sh
./build.sh
open patchbay.app
```

On first rack enable, macOS asks for System Audio Recording permission.

The rack is deliberately off at launch: patchbay never seizes system audio
without being asked.

## License

[GPLv3](LICENSE)

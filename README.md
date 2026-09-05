# patchbay

A native, open-source DSP rack for macOS system audio. No virtual audio driver.

<p align="center">
  <img src="screenshot.png" width="398" alt="patchbay devices page">
  <img src="rack.png" width="666" alt="patchbay rack page with AutoEq profile">
</p>

## What it does

- **Modular effects chain** on all system audio, reorderable by drag, up to 16 modules:
  - Tone: Gain, Parametric EQ (up to 32 bands: bell, shelves, pass, notch), 16-band Graphic EQ, Filter (12–48 dB/oct), Loudness
  - Character: Bass enhancer, Exciter, Crystalizer, Crusher
  - Dynamics: Compressor, Expander, Gate, De-esser, Limiter, Maximizer, Autogain
  - Space: Stereo tools, Crossfeed, Delay, Reverb (Freeverb)
- **AutoEq headphone correction**: search 8,800+ profiles from [jaakkopasanen/AutoEq](https://github.com/jaakkopasanen/AutoEq), applied as a parametric module in one click
- **Equalizer APO import/export**: `ParametricEQ.txt` in, `ParametricEQ.txt` out
- **Per-device chains**: every output device remembers its own rack
- **Bypass** for instant A/B, input/output metering
- **Output and input device switching**, hardware volume and mic gain
- **eqMac recovery** tools (fix stuck audio, restart, reset Core Audio)

## How it works

patchbay uses the Core Audio process-tap API (macOS 14.2+) instead of installing
a virtual audio driver:

```text
system audio → process tap → [ module → module → … ] → output device
```

The tap and the current output device are combined into a private aggregate
device. An IO proc on that aggregate reads the tapped mix, runs the chain, and
writes the result to the hardware. Nothing is installed into the system.

Safety properties of this design:

- **Capture is proven before muting.** The tap starts unmuted; only after real
  samples arrive and the output layout is confirmed does the engine rebuild with
  a muted tap. A denied permission or unsupported device cannot silence the Mac.
- **Crashes cannot strand audio.** If patchbay dies, coreaudiod destroys the
  private tap and aggregate and the real device remains the default output.
- **Realtime path is allocation-free and lock-free.** The UI publishes immutable
  config snapshots through an atomic pointer (`DSPConfig.c`); filter memory is
  kept across parameter changes so slider moves never click. Output is NaN-guarded.

Tap topology is switchable from the rack footer (`⋯`): *Stereo mixdown*
(default, works everywhere) or *Device stream* (tap bound to the hardware
stream, no resampling; behaviour varies per device).

## Limits

- **Input effects need a virtual device.** Process taps only intercept output.
  Applying the chain to a microphone so other apps receive it requires an
  AudioServerPlugIn driver, which is exactly what patchbay avoids. Input device
  selection and gain are supported; input processing is not.
- **One tap processor at a time.** Running patchbay alongside another
  `mutedWhenTapped`-based app (FineTune, CoreEQ) chains two muting processors
  on one device; results range from double latency to silence.
- Not ported from EasyEffects: convolver, multiband compressor/gate, pitch,
  RNNoise/DeepFilterNet noise reduction, echo cancellation, speech processor.

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

[GPLv3](LICENSE). AutoEq data is MIT-licensed by Jaakko Pasanen and contributors.

# patchbay.

A native, open-source DSP rack and per-app router for macOS system audio. No virtual audio driver for output; an optional one for the microphone.

<p align="center">
  <img src="screenshot.png" width="426" alt="patchbay devices page">
  <img src="rack.png" width="566" alt="patchbay rack page with AutoEq profile">
</p>

[Download patchbay.dmg](https://github.com/azain47/patchbay/releases/latest/download/patchbay.dmg) ·
[Watch the 45-second demo](https://github.com/azain47/patchbay/releases/download/v1.3.0/patchbay-linkedin.mp4)

The demo is silent.

## Install

Requires an Apple Silicon Mac on macOS 15 or newer.

1. Open `patchbay.dmg` and drag patchbay into Applications.
2. Open patchbay. macOS says it can't verify the developer, because patchbay is
   signed with its own certificate rather than a paid Apple Developer ID.
   Open System Settings → Privacy & Security, scroll down, click *Open Anyway*
   next to patchbay, and confirm. Only do this if you trust this repository;
   you can also build from source instead.
3. Click the patchbay icon in the menu bar and turn the rack on. macOS asks for
   System Audio Recording permission once.

After that, patchbay updates itself. It checks for a new release once a day
and asks before installing (Settings → Updates to turn checks off or check now).
Each update is verified against the project's update-signing key and must carry
the same code signature as the installed app, which also keeps the audio
permission across updates. Versions before 1.4.0 have no updater: download the
DMG once.

## What it does

- **Modular effects chain** on all system audio, reorderable by drag, up to 16 modules:
  - Tone: Gain, Parametric EQ (up to 32 bands: bell, shelves, pass, notch), 16-band Graphic EQ, Filter (12–48 dB/oct), Loudness
  - Character: Bass enhancer, Exciter, Crystalizer, Crusher
  - Dynamics: Compressor, Expander, Gate, De-esser, Limiter, Maximizer, Autogain
  - Space: Stereo tools, Crossfeed, Delay, Reverb (Freeverb)
- **Contextual chain placement**: a new module lands where it belongs in the
  signal path, after the last module of an earlier or equal stage. The order is
  gain staging → gate/expander → de-esser → filter/EQ → compressor/autogain →
  saturation → stereo/time effects → loudness → maximizer → limiter. Existing
  modules are never moved; drag if you want something else. A new EQ filter is
  inserted at the top of the list.
- **Headphone correction** in one search, applied as a parametric module in one
  click. *All sources* (the default) searches
  [jaakkopasanen/AutoEq](https://github.com/jaakkopasanen/AutoEq)'s 8,800+
  ready-made corrections (oratory1990, crinacle, Rtings, …) and every reviewer
  database listed on [squig.link](https://squig.link) (130+) at once; results
  are grouped by source and labelled with the reviewer and rig. Picking a
  squig.link measurement does the manual steps for you: patchbay loads the
  measurement, picks a target, computes the correction and fits the filters.
  The **Target** chip chooses the kind of curve: *Harman* (the reviewer's Harman
  curve for that kind of phone, in-ear or over-ear) or *Neutral* (their
  diffuse-field curve). Loudspeaker/room curves and "targets" that are really
  another phone's measurement are skipped. If the site lacks the file or has no
  suitable curve, AutoEq's published Harman or diffuse-field curve is used
  instead (5128 rigs only fall back to diffuse field, since Harman's curves were
  defined on other rigs). The module name records the database and target used.
  Narrow the source to one squig.link database to choose any of its targets
  yourself. Hangout.Audio (crinacle's own site) and other databases that opted
  out of third-party access are not offered; crinacle's measurements reach the
  app through AutoEq.
- **Any filter count**: AutoEq publishes ten filters per profile; ask for 5 to
  32 and patchbay fits its own from the full-resolution correction (on the HD
  650 the 10-filter fit lands within 0.25 dB RMS of the target, better than
  the published ten; 16 filters halve that).
- **Equalizer APO import/export**: `ParametricEQ.txt` in, `ParametricEQ.txt` out
- **Per-device chains**: every output device remembers its own rack
- **Presets**: save the chain under a name and recall it on any device, route
  or the microphone. Bind a preset to an output (the bookmark on its row in the
  output list, or *Load on …* in the preset menu) and switching to that output
  loads it. A preset saved from the system chain is bound to the current output.
  Working-chain edits auto-save without overwriting the named preset; use
  *Update “name”* to replace that saved preset.
  **No preset** empties the chain and clears its preset label; on outputs it
  also removes automatic preset loading. This works from the main preset
  menu, *Load on …*, and the output's bookmark menu. Saved presets remain
  available. Clearing the chain being edited is undoable; undo restores the
  chain, not the output's automatic-loading assignment.
- **Undo/redo**: the rack footer has Undo and Redo buttons; use **⌘Z** and
  **⇧⌘Z** while the rack is open. Each slider drag is one step. Band edits,
  module additions/removals/reordering, preset loads, bypass and resets are
  reversible. Each output, microphone and app route has separate history
  (up to 100 steps, held until the app quits). New edits clear redo. Restoring
  a chain auto-saves it without overwriting presets or changing processing
  on/off. Text fields use their own history instead of undoing the rack.
- **EQ accuracy**: the response graph is computed from the same coefficients at
  the device's own sample rate, so what you see is what is rendered. Coefficient
  changes glide over 10 ms: dragging a fader, switching a band off or changing its
  type does not click.
- **Bypass** for instant A/B, input/output metering, **device sample rate** picker in the rack footer
- **Output and input device switching**, hardware volume, mic gain and hardware mic mute
- **eqMac recovery** tools (fix stuck audio, restart, reset Core Audio) on the Fix page
- **App routing**: send one app to a different output device, with its own
  chain. Everything not routed keeps using the system chain. Helper processes
  (browser renderers, Electron utilities) follow their app; command-line
  players (`afplay`, `mpv`, `ffplay`) are routed by executable name.

## Interface

One menu bar popover with five icon tabs: output, input, routes, rack, fix.
Tab icons stay fixed; only the selection pill slides. Incoming pages fade in
at their final position, without directional movement or inherited control
animations. The popover changes size immediately rather than running a second
AppKit resize animation over the SwiftUI transition.
The sidebar and graph animate their occupied width and height, keeping their
contents mounted instead of inserting them at full size. Hidden graphs stop
requesting spectrum updates. Chain and band selections travel between items;
response curves morph, buttons respond on press, and sliders animate external
value changes while following the pointer directly during a drag.

- **Layout** follows the page by default (*Auto*): one width, device pages
  compact and only as tall as their content, the rack spacious and capped at
  680 pt with the module editor scrolling inside. *Compact*, *Comfortable* and
  *Spacious* pin one density everywhere. The popover is always dark.
- **Settings** live behind the gear in the footer: layout, *Stay open*
  (otherwise a click anywhere else closes the window), the shift step, accent
  colour, audio capture topology, and the virtual microphone driver.
- **Notices** (preset loaded, import failed, …) replace the footer status for a
  few seconds rather than floating over the page. When the rack is off, a banner
  on the rack page says so, with a button to turn it on.
- The chain is a vertical column beside the module editor in signal order, first
  stage on top. Click a row to edit it, press and drag to reorder (the row
  follows the pointer, the others slide out of its way), dot to bypass one
  module. The sidebar button in the rack footer hides the column; the editor's
  title then becomes the module picker, with *Add* inside it. A badge beside the
  wordmark says when the rack is editing a route or the microphone rather than
  the system chain. Profile modules show the headphone name, with the source
  underneath; long names truncate and show in full on hover.
- The **preset bar** under the chain header shows which preset the chain came
  from, with a dot once you have edited past it, and whether the current output
  auto-loads it. Its menu applies a preset, saves the chain as a new one,
  updates, renames or deletes the current one, and picks the preset to load on
  this output. With the column hidden the same items live in the module picker.
- **Sliders**: hold shift while dragging for fine control. The drag turns
  relative and slows to the *Shift step* set in Settings (½ to 1⁄50 of pointer
  travel), and a bubble on the knob shows the value being dialled. Applies to
  every slider, including the EQ gain columns.
- **Parametric EQ** is a row of vertical gain faders, one per filter, low to
  high frequency. Tap a column to edit its type, frequency and Q in the rows
  below; the currently selected column is highlighted. Once the columns no
  longer fit the editor, the row scrolls sideways. The chips under the search
  field pick the source (AutoEq or a squig.link database), the filter count,
  and for squig.link the target curve to correct towards.
- **Graph** (the pulse button in the rack footer) toggles a panel showing the
  combined frequency response of every enabled linear module (EQs, filters,
  loudness, gain) as a solid curve, the selected module's own curve dashed
  when it differs, and a live spectrum of the processed output behind them.
  Dynamics, saturation and space modules have no fixed response and are not
  drawn. The analyser only runs while the panel is visible.
- **Routes** lists each app → device pair with a live status dot (waiting for
  the app, processing, error). The `+` menu offers every app currently
  connected to Core Audio. The sliders button on a row opens that route's chain
  in the rack; a scope chip at the top of the chain column switches between
  the system chain and each route. The header switch and footer status refer
  to the route being edited only while the rack page is in front.

## How it works

patchbay uses the Core Audio process-tap API (macOS 14.2+) instead of installing
a virtual audio driver:

```text
system audio (minus routed apps) → system tap → [ chain ] → default device
app A                             → route tap  → [ chain ] → device X
```

Each tap and its output device are combined into a private aggregate device.
An IO proc on that aggregate reads the tapped mix, runs the chain, and writes
the result to the hardware. A route's tap is a stereo mixdown of exactly that
app's processes; the system tap excludes them so nothing is captured twice.
When an app's process set changes, the live tap's description is updated in
place (`kAudioTapPropertyDescription`); the pipeline is only rebuilt if the
HAL refuses. Nothing is installed into the system.

Safety properties of this design:

- **Capture is proven before muting.** The tap starts unmuted; only after real
  samples arrive and the output layout is confirmed does the engine rebuild with
  a muted tap. A denied permission or unsupported device cannot silence the Mac.
- **Crashes cannot strand audio.** If patchbay dies, coreaudiod destroys the
  private tap and aggregate and the real device remains the default output.
- **Realtime path is allocation-free and lock-free.** The UI publishes immutable
  config snapshots through an atomic pointer (`DSPConfig.c`); filter memory is
  kept across parameter changes so slider moves never click. Output is NaN-guarded.
- **Routes prove capture once.** A route whose app goes quiet keeps its proof,
  so the app's next sound is captured muted immediately instead of leaking a
  proof window to the default device.

Tap topology is chosen in Settings → Audio capture. *Stereo mixdown* (default)
has Core Audio mix every process to one stereo stream in its own format, which
patchbay processes and the aggregate resamples to the device rate when they
differ; it works on every device. *Device stream* binds the tap to the output
device's hardware stream, so the format matches exactly and nothing is
resampled; cleaner on paper, but some devices deliver silence, so it is opt-in.

## Limits

- **Input effects need a virtual device.** Process taps only intercept output.
  Putting the chain on a microphone so other apps receive it needs something
  that looks like an input device, which is why the microphone chain is the one
  opt-in that installs a driver (see *Microphone* below). Without it, input
  device selection, gain and mute still work.
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

`build.sh` downloads [Sparkle](https://sparkle-project.org) 2.10.0 (MIT, the
updater) once into `.build/` and checks its SHA-256. Without the project's
signing certificate the build is ad-hoc signed; it runs, but macOS asks for
audio permission again after every rebuild.

On first rack enable, macOS asks for System Audio Recording permission.
The rack is deliberately off at launch: patchbay never seizes system audio
without being asked.

## Releasing

`main` and `staging` are protected: no direct pushes, force-pushes or deletion.
Work lands on `staging` through a pull request, then `staging` → `main` through
another. To release, tag a commit on `main` with an annotated tag; its message
is the release notes, shown on GitHub and in the update prompt:

```sh
git switch main && git pull
git tag -a v1.4.1 -m "## Fixes
- …" && git push origin v1.4.1
```

The workflow refuses tags whose commit is not on `main`.

`.github/workflows/release.yml` builds with `scripts/release.sh`, signs the app
and DMG, writes `appcast.xml` (the update feed, signed with Sparkle's EdDSA
key) and publishes both on the release. Installed copies read the feed from
`releases/latest/download/appcast.xml`. Repository secrets:

| Secret | Contents |
|---|---|
| `SIGNING_P12_BASE64` | base64 of the "patchbay Code Signing" certificate and key (.p12) |
| `SIGNING_P12_PASSWORD` | the .p12 password |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key (`generate_keys -x`) |

Losing either key means installed copies can no longer update; users would
have to download a new DMG by hand.

## Microphone

The one feature that touches the system. Settings → *Virtual microphone* → *Install*
copies a 90 KB passthrough loopback driver into
`/Library/Audio/Plug-Ins/HAL/patchbayMic.driver` (asks for an administrator
password, restarts Core Audio for about three seconds). The driver is
[BlackHole](https://github.com/ExistentialAudio/BlackHole) (GPLv3, Existential
Audio) built as two devices sharing one ring buffer: "patchbay Mic", visible and
input-only, which apps select; and a hidden output-only sink the engine writes
into, so the engine can never read back its own output. The source and
build script are in `VirtualMic/`. It has no logic of its own: whatever is
written to its output stream appears on its input stream.

```text
real microphone → [ microphone chain ] → patchbay Mic → Zoom, Discord, OBS…
```

With the driver installed, the switch on the Input page runs the chain from the
selected real microphone into patchbay Mic and makes patchbay Mic the default
input, so apps pick it up without configuration. Turning it off hands the
default input back to the real microphone. The chain is edited in the rack via
the scope chip (*Microphone*) and is remembered per microphone.

On quit, and whenever the engine cannot run (driver missing, no microphone),
patchbay hands the default input back to the real microphone, so apps are not
left listening to a silent device. That covers Quit, logout and SIGTERM; after
a crash the hand-back happens on the next launch. Expect roughly 10 ms of added
latency.
*Remove* in Settings deletes the driver and restarts Core Audio again.

## License

[GPLv3](LICENSE). AutoEq data is MIT-licensed by Jaakko Pasanen and contributors. The virtual microphone driver is BlackHole, GPLv3 © Existential Audio Inc. (`VirtualMic/LICENSE`). The updater is Sparkle, MIT © the Sparkle Project contributors (license bundled at `patchbay.app/Contents/Resources/Sparkle-LICENSE`).

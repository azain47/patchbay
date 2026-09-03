# AudioFix

A small macOS menu bar utility for recovering eqMac audio routing.

## Build

Requires macOS 14+ and the Xcode Command Line Tools.

```sh
./build.sh
open AudioFix.app
```

AudioFix uses CoreAudio to show output devices, switch the default output, restart eqMac, and reset CoreAudio when needed.

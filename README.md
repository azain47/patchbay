# patchbay

A small macOS menu bar utility for recovering eqMac audio routing.

![patchbay menu bar popover](screenshot.png)

## Build

Requires macOS 14+ and the Xcode Command Line Tools.

```sh
./build.sh
open patchbay.app
```

patchbay uses CoreAudio to show output devices, switch the default output, restart eqMac, and reset CoreAudio when needed.

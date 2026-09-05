#!/bin/bash
# Removes the patchbay Mic driver and restarts Core Audio. Same as Settings → Remove.
set -e
sudo rm -rf /Library/Audio/Plug-Ins/HAL/patchbayMic.driver
sudo killall coreaudiod
echo "patchbay Mic removed"

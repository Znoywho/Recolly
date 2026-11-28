#!/usr/bin/env bash
# Dev-only: play audio files into the Android emulator's microphone (PipeWire/PulseAudio on Linux).
#
# Creates a virtual speaker "recolly_mic" and makes its monitor the default mic, so the emulator
# (started with `emulator -avd <name> -allow-host-audio`, and "Virtual microphone uses host audio input"
# ON in Extended controls → Microphone) hears exactly the file, not your room.
# For each file: tap record in the app, press Enter here, wait for it to finish, tap stop.
# The old default mic is restored on exit (Ctrl+C too).
#
# Usage: server/scripts/emulator_mic.sh ~/recolly-test-files/*.m4a
set -euo pipefail

old_source=$(pactl get-default-source)
module=$(pactl load-module module-null-sink sink_name=recolly_mic sink_properties=device.description=RecollyMic)
trap 'pactl set-default-source "$old_source"; pactl unload-module "$module"' EXIT
pactl set-default-source recolly_mic.monitor

for file in "$@"; do
  read -rp "Next: $(basename "$file") — tap record in the app, then press Enter "
  # ffmpeg decodes any format (m4a included), pacat plays it into the virtual speaker
  ffmpeg -loglevel error -i "$file" -f s16le -ac 1 -ar 16000 - \
    | pacat --device=recolly_mic --format=s16le --rate=16000 --channels=1
  sleep 1  # a short silence so the end of the sentence is not cut when you tap stop
  echo "  done — tap stop"
done

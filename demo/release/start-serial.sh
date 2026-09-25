#!/usr/bin/env bash
# Connects the Pugputer's serial port to a serial device or a new pseudo-terminal, for a
# terminal program (screen, picocom, minicom, ...) to use as the console. See README.md.
echo "This connects the Pugputer's serial port to a serial device, or to a new"
echo "pseudo-terminal that a terminal program (screen, picocom, minicom, ...) can open at"
echo "19200 baud, 8 data bits, no parity, 1 stop bit. See README.md."
echo
read -r -p "Serial device (for example /dev/ttyUSB0), or Enter for a pseudo-terminal: " PORT
"$(dirname "$0")/pugputer" --com "${PORT:-pty}"
echo
echo "The emulator has stopped."

#!/bin/bash

# This script is run whenever the desktop environment has started.
# (with normal user privileges).

script_dir=$(dirname -- "$(readlink -nf $0)";)
source "$script_dir/header.sh"
validate_linux

export LD_PRELOAD="/lib/x86_64-linux-gnu/libudev.so.1 /lib/x86_64-linux-gnu/libselinux.so.1 /lib/x86_64-linux-gnu/libz.so.1 /lib/x86_64-linux-gnu/libgdk-x11-2.0.so.0"

# Locate the Vivado install. 2026.1 lays out as /home/user/Xilinx/<version>/Vivado;
# releases up to 2024.x used /home/user/Xilinx/Vivado/<version>. The old glob below silently expanded to a
# literal unmatched path on 2026.1, so Vivado never launched. Check for the actual
# binary instead of just the Xilinx folder.
vivado_dir=""
for candidate in /home/user/Xilinx/*/Vivado /home/user/Xilinx/Vivado/*
do
	if [ -x "$candidate/bin/vivado" ]
	then
		vivado_dir="$candidate"
		break
	fi
done

if [ -n "$vivado_dir" ]
then
	# Make Vivado connect to the xvcd server running on macOS
	"$vivado_dir/bin/hw_server" -e "set auto-open-servers     xilinx-xvc:host.docker.internal:2542" &
	# Source, don't execute: running settings64.sh as a subprocess (as this
	# script used to) throws its exports away, so Vivado started without them.
	. "$vivado_dir/settings64.sh"
	# Still launched by absolute path so the GUI comes up even if PATH is odd.
	"$vivado_dir/bin/vivado"
else
	f_echo "The installation is incomplete."
	wait_for_user_input
fi
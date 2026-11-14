#!/bin/zsh

# Attempts to configure Docker by enabling Rosetta and raising the VM's swap
# and memory allocation.

script_dir=$(dirname -- "$(readlink -nf $0)";)
source "$script_dir/header.sh"
validate_macos

# Swap the VM should have at least. Vivado is memory hungry under Rosetta.
min_swap=4096

# Memory the VM should have at least, and what we aim for. Docker Desktop's
# stock allocation is 8 GiB, which is not enough for synthesis of mid-sized
# designs: the Linux OOM killer ends Vivado with no Vivado-level error, only
#   /home/user/Xilinx/.../rdiArgs.sh: line 60: NNNN Killed  "$RDI_PROG" "$@"
# (exit status 137 = SIGKILL). 16 GiB is a good target -- but do not simply go
# bigger: on a 32 GB Mac, 20 GiB starves macOS, which then kills the terminal
# driving the build while the VM itself sits half idle.
min_memory=12288
want_memory=16384

# Leave this much for macOS itself.
reserve_for_macos=8192

function cannot_setup_docker {
    f_echo "Unfortunately, the script could not configure Docker automatically."
    f_echo "This means that you have to change the settings in the Docker Dashboard yourself"
    f_echo "(Settings -> Resources):"
    f_echo "Enable the Virtualization Framework and Rosetta emulation, set Swap to at least"
    f_echo "$((min_swap / 1024)) GiB and Memory to at least $((min_memory / 1024)) GiB."
    f_echo "Restart Docker after applying the changes and then continue with the installation."
    wait_for_user_input
    exit 1
}

# Docker Desktop renamed settings.json to settings-store.json and switched the
# keys from camelCase to PascalCase (settings-store.json confirmed on 4.92). A
# fresh install writes only the handful of keys it has been asked about, so the
# resource keys are typically ABSENT rather than present-with-a-default -- which
# is why the old grep-and-sed approach silently did nothing. Edit the JSON
# properly instead, and support either file.
docker_settings_dir="$HOME/Library/Group Containers/group.com.docker"
if [ -f "$docker_settings_dir/settings-store.json" ]
then
    docker_settings_file="$docker_settings_dir/settings-store.json"
    key_style="pascal"
elif [ -f "$docker_settings_dir/settings.json" ]
then
    docker_settings_file="$docker_settings_dir/settings.json"
    key_style="camel"
else
    cannot_setup_docker
fi

# Editing JSON with sed cannot insert absent keys, so use python3. On macOS,
# /usr/bin/python3 is a stub until the Xcode command line tools are installed,
# so check that it actually runs rather than that it exists.
if ! python3 -c '' > /dev/null 2>&1
then
    f_echo "python3 not found (install the Xcode command line tools: xcode-select --install)"
    cannot_setup_docker
fi

stop_docker

# Clamp the target to what the machine can actually spare.
physical_mib=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
max_memory=$(( physical_mib - reserve_for_macos ))
if [ "$want_memory" -gt "$max_memory" ]
then
    want_memory=$max_memory
fi
if [ "$want_memory" -lt "$min_memory" ]
then
    f_echo "Warning: this Mac has $((physical_mib / 1024)) GiB of RAM, so Docker can be given"
    f_echo "at most $((want_memory / 1024)) GiB while leaving $((reserve_for_macos / 1024)) GiB for macOS."
    f_echo "Large designs may still be killed by the OOM killer (exit status 137)."
fi

cp "$docker_settings_file" "$docker_settings_file.bak"

python3 - "$docker_settings_file" "$key_style" "$want_memory" "$min_swap" <<'PYTHON_EOF'
import json
import sys

path, style, want_memory, min_swap = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])

names = {
    "pascal": ("UseVirtualizationFramework", "UseVirtualizationFrameworkRosetta",
               "SwapMiB", "MemoryMiB"),
    "camel": ("useVirtualizationFramework", "useVirtualizationFrameworkRosetta",
              "swapMiB", "memoryMiB"),
}
vz, rosetta, swap_key, memory_key = names[style]

try:
    with open(path) as handle:
        settings = json.load(handle)
except (OSError, ValueError) as exc:
    print("could not read %s: %s" % (path, exc), file=sys.stderr)
    sys.exit(1)

settings[vz] = True
settings[rosetta] = True
# Only ever raise these -- never shrink a VM the user deliberately made larger.
settings[swap_key] = max(int(settings.get(swap_key) or 0), min_swap)
settings[memory_key] = max(int(settings.get(memory_key) or 0), want_memory)

try:
    with open(path, "w") as handle:
        json.dump(settings, handle, indent=2)
except OSError as exc:
    print("could not write %s: %s" % (path, exc), file=sys.stderr)
    sys.exit(1)

print("%s = %d MiB, %s = %d MiB" % (memory_key, settings[memory_key],
                                    swap_key, settings[swap_key]))
PYTHON_EOF

if [ $? -ne 0 ]
then
    mv "$docker_settings_file.bak" "$docker_settings_file"
    cannot_setup_docker
fi

f_echo "Configured Docker successfully"

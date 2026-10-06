# shellcheck shell=sh
# Runs on the VPS's stock system (piped to `sh -s` by `nixod probe`).
# Read-only: prints one JSON object describing what the hub's NixOS config
# needs (boot mode, network, disks). Uses only tools any distro has.

json_list() { # json_list <items...>: ["a","b"]
  sep=
  printf '['
  for item in "$@"; do
    printf '%s"%s"' "$sep" "$item"
    sep=,
  done
  printf ']'
}

if [ -d /sys/firmware/efi ]; then boot=uefi; else boot=bios; fi

resolv=/etc/resolv.conf
# systemd-resolved: the real upstream servers, not 127.0.0.53.
[ -e /run/systemd/resolve/resolv.conf ] && resolv=/run/systemd/resolve/resolv.conf
# shellcheck disable=SC2046
nameservers=$(json_list $(awk '/^nameserver/ { print $2 }' "$resolv"))

by_id=
sep=
for link in /dev/disk/by-id/*; do
  [ -e "$link" ] || continue
  by_id="$by_id$sep\"$link\":\"$(readlink -f "$link")\""
  sep=,
done

# shellcheck disable=SC1091
os=$(. /etc/os-release && printf '%s %s' "$ID" "${VERSION_ID:-}")

# Storage and network drivers in use: the hub's initrd needs the same.
# shellcheck disable=SC2046
modules=$(json_list $(awk '{ print $1 }' /proc/modules | grep -E '^(virtio|vmw|xen|hv_|nvme|ahci|ata_piix|sd_mod|sr_mod|e1000|ixgbe)' | sort))

cat <<EOF
{
  "os": "$os",
  "arch": "$(uname -m)",
  "virtualization": "$(systemd-detect-virt 2>/dev/null || echo unknown)",
  "boot": "$boot",
  "memoryKiB": $(awk '/^MemTotal/ { print $2 }' /proc/meminfo),
  "interfaces": $(ip -j address show),
  "routes4": $(ip -j -4 route show),
  "routes6": $(ip -j -6 route show),
  "nameservers": $nameservers,
  "disks": $(lsblk -J -b -o NAME,PATH,SIZE,TYPE,MODEL,FSTYPE,MOUNTPOINT),
  "diskById": {$by_id},
  "kernelModules": $modules
}
EOF

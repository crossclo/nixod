# Adds .summary to `nixod probe`'s JSON: what the hub's config needs, worked
# out from the raw `ip -j`, lsblk and /proc output, and warnings.
#   jq --arg localArch "$(uname -m)" -f probe-summary.jq
# The playbook (nixod doc hub) explains each field.

def ip4int: split(".") | map(tonumber) | .[0] * 16777216 + .[1] * 65536 + .[2] * 256 + .[3];
# Same subnet: the same address once the host bits are dropped.
def samenet4($a; $b; $prefix):
  pow(2; 32 - $prefix) as $size
  | (($a | ip4int) / $size | floor) == (($b | ip4int) / $size | floor);

. as $p
| ([$p.routes4[]? | select(.dst == "default")] | first) as $route4
| ([$p.routes6[]? | select(.dst == "default")] | first) as $route6
# The interface with the default route, else the first one that isn't lo.
| (($route4.dev // $route6.dev)
    // ([$p.interfaces[] | select(.ifname != "lo") | .ifname] | first)) as $ifname
| ([$p.interfaces[] | select(.ifname == $ifname)] | first) as $if
| ([$if.addr_info[]? | select(.family == "inet" and .scope == "global")] | first) as $a4
| ([$if.addr_info[]? | select(.family == "inet6" and .scope == "global")]) as $a6s
| ([$a6s[] | select(.dynamic != true)] | first) as $a6static
| ([$p.disks.blockdevices[]? | select(.type == "disk")] | sort_by(.size | tonumber) | reverse) as $disks
| ($disks | first) as $disk
| ([$p.diskById // {} | to_entries[] | select(.value == $disk.path) | .key]
    | sort_by(if test("/(wwn|nvme-eui)-") then 1 else 0 end) | first) as $byId
| {
    interface: $ifname,
    ipv4: (
      if $a4 == null then { method: "none" }
      elif ($a4.dynamic == true or $route4.protocol == "dhcp") then
        { method: "dhcp", address: $a4.local, prefixLength: $a4.prefixlen }
      else
        { method: "static", address: $a4.local, prefixLength: $a4.prefixlen,
          gateway: $route4.gateway }
      end
      | if $a4 != null and $route4.gateway != null then
          # A gateway outside the address's subnet (a /32 address) needs an
          # on-link route before the default route.
          .gatewayOutsideSubnet = (samenet4($a4.local; $route4.gateway; $a4.prefixlen) | not)
        else . end
    ),
    ipv6: (
      if $a6static != null then
        { method: "static", address: $a6static.local, prefixLength: $a6static.prefixlen,
          gateway: $route6.gateway }
      elif ($a6s | length) > 0 then { method: "slaac" }
      else { method: "none" }
      end
    ),
    nameservers: $p.nameservers,
    disk: (if $disk == null then null else
      { path: $disk.path, byId: $byId, sizeGiB: ($disk.size | tonumber / 1073741824 | floor) } end),
    warnings: (
      [ if $p.memoryKiB < 1500000 then
          "only \($p.memoryKiB / 1024 | floor) MiB of RAM: the NixOS installer runs in RAM and needs about 1.5 GB; the install may fail or hang. A bigger plan is safer."
        else empty end,
        if $localArch != "" and $p.arch != $localArch then
          "the VPS is \($p.arch), this machine is \($localArch): it can't build the hub as is (it needs emulation, boot.binfmt, or a remote builder)."
        else empty end,
        if $a4 == null then
          "no global IPv4 address on \($ifname): check the network by hand."
        else empty end,
        if ($disks | length) > 1 then
          "\($disks | length) disks: the biggest (\($disk.path)) is picked; check it's the one to install on."
        else empty end,
        if $disk == null then "no disk found." else empty end
      ]
    )
  } as $summary
| { summary: $summary } + $p

# hub: write hosts/<hub>/ from `nixod probe`

`nixod probe root@<ip>` prints what the VPS runs now. Turn it into
`hosts/<hub>/default.nix` and `hosts/<hub>/disko.nix`.
`hardware-configuration.nix` comes later, from `nixod install-hub --stage hardware`.

## First: can this VPS run the hub?

- `memoryKiB`: the installer runs in RAM (kexec) and needs about 1.5 GB. Below
  1500000, warn the user that the install may fail or hang, and suggest a
  bigger plan.
- `arch`: `x86_64` or `aarch64`. If it isn't this machine's (`uname -m`), this
  machine can't build the hub as is (it needs emulation, `boot.binfmt`, or a
  remote builder). Tell the user before going on.

## Network

Find the interface with the public address in `interfaces`. Decide each
address family on its own:

- **IPv4**: look at the global IPv4 address (not `127.*`). `"dynamic": true`
  → DHCP: `networking.useDHCP = true;` (or `networking.interfaces.<if>.useDHCP`).
  Otherwise static: copy the address and prefix length, the `default` route's
  gateway from `routes4`, and `nameservers`.
- **IPv6**: ignore `fe80::` link-local addresses (always there, never
  dynamic). A global address with `"dynamic": true` comes from router
  advertisements (SLAAC): leave it to the kernel, write nothing. A global
  address without it is static: copy it, and the `default` route of `routes6`
  (often `fe80::1`, on the interface).
- **Gateway outside the subnet** (a `/32` address, as at OVH, Hetzner and
  others; or a gateway that isn't inside the address's prefix): the default
  route alone fails. Declare the route to the gateway as on-link first:

```nix
networking.interfaces.eth0.ipv4.routes = [
  { address = "203.0.113.1"; prefixLength = 32; }   # the gateway, on-link
];
networking.defaultGateway = { address = "203.0.113.1"; interface = "eth0"; };
```

The interface name can differ under NixOS; with a single NIC, pin it. A
static example:

```nix
networking = {
  usePredictableInterfaceNames = false;   # the only NIC is eth0
  useDHCP = false;
  interfaces.eth0 = {
    ipv4.addresses = [ { address = "203.0.113.10"; prefixLength = 24; } ];
    ipv6.addresses = [ { address = "2001:db8::1"; prefixLength = 64; } ];
  };
  defaultGateway = { address = "203.0.113.1"; interface = "eth0"; };
  defaultGateway6 = { address = "fe80::1"; interface = "eth0"; };
  nameservers = [ "203.0.113.53" ];
};
```

## Boot and drivers

- `"virtualization": "kvm"` (or qemu): import `(modulesPath + "/profiles/qemu-guest.nix")`.
- `kernelModules`: don't copy them. The hardware configuration (generated
  later on the VPS itself, by `install-hub --stage hardware`) already lists the
  ones NixOS needs; a module name from the provider's distribution may not
  exist in NixOS and breaks the build. Add one only if the generated file
  lacks it.
- `"boot": "bios"`: GRUB on the disk's BIOS boot partition (disko fills
  `grub.devices`). `"uefi"`: GRUB with EFI, or systemd-boot. The hybrid below
  boots either way:

```nix
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  # networking = { ... };
  system.stateVersion = "26.05";   # the release it is installed with
}
```

## Disk (disko.nix)

Pick the disk from `disks` (type `disk`, the biggest). Use its stable name from
`diskById` when there is one, else its path (`/dev/sda`, `/dev/vda`).

```nix
{
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/<id>";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = { size = "1M"; type = "EF02"; };   # BIOS boot (GRUB)
        ESP = {
          size = "512M";
          type = "EF00";
          content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; mountOptions = [ "umask=0077" ]; };
        };
        root = {
          size = "100%";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; mountOptions = [ "noatime" ]; };
        };
      };
    };
  };
}
```

When the provider's setup doesn't fit (an unusual boot, network or disk), adapt
these files, or pass flags through: `nixod install-hub ... -- <nixos-anywhere
flags>`. Tell the user what you do differently and why.

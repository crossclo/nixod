# hub: write hosts/<hub>/ from `nixod probe`

`nixod probe root@<ip>` prints what the VPS runs now. Turn it into
`hosts/<hub>/default.nix` and `hosts/<hub>/disko.nix`.
`hardware-configuration.nix` comes later, from `nixod install-hub --stage hardware`.

## Network

In `interfaces`, the interface with the public address:

- every address has `"dynamic": true` → DHCP: `networking.useDHCP = true;`
- otherwise static: copy addresses, prefix lengths, gateways (`routes4`,
  `routes6`: the `default` route) and `nameservers`. The interface name can
  differ under NixOS; with a single NIC, pin it:

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
- `kernelModules`: add them to `boot.initrd.availableKernelModules`.
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
  system.stateVersion = "25.11";   # the release it is installed with
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

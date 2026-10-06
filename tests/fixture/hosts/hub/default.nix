# Dummy hub: a KVM VPS with DHCP, booting BIOS or UEFI.
{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  networking.useDHCP = true;

  # Hybrid GRUB: BIOS through the EF02 partition (disko fills grub.devices),
  # removable EFI as a fallback.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  system.stateVersion = "25.11";
}

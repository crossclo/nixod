# Fake hub hardware configuration (generated with --no-filesystems:
# disko declares the file systems).
{ lib, ... }:

{
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "ahci"
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "sd_mod"
    "sr_mod"
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

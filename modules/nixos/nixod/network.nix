# Which machine this is, and the whole (validated) network.nix.
# Set by lib.mkNetwork.
{ config, lib, ... }:

{
  options.nixod = {
    name = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "This machine's name in network.nix.";
    };

    network = lib.mkOption {
      type = lib.types.raw;
      default = {
        machines = { };
        folders = { };
      };
      description = "The instance's network.nix.";
    };
  };
}

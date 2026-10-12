# Turns a block of config into defaults: every leaf gets priority 900, so
# an instance can override any single value (one git setting, one
# sysctl) with a plain definition and keep the rest. 900 sits above the
# lib.mkDefault (1000) that NixOS and Home Manager use for their own
# defaults, so nixod's values still win over those.
#
# Lists are leaves too: setting one replaces it. Values that already carry
# a priority or condition (mkIf, mkForce, mkOptionDefault...) and
# derivations are left as they are. Additive things (packages, plugins,
# startup commands) stay outside this helper, at normal priority, so they
# merge with the user's instead.
{ lib }:

lib.mapAttrsRecursiveCond (as: !(lib.isDerivation as) && !(as ? _type)) (
  _: v: if v ? _type then v else lib.mkOverride 900 v
)

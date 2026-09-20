{
  inputs,
  pkgs,
  system,
  ...
}:

let
  # The upstream bar has no layout option. Keep the source and patch in Nix so
  # the custom order remains reproducible across every host and update.
  patchedShell = pkgs.applyPatches {
    name = "ambxst-patched-shell";
    src = inputs.ambxst;
    prePatch = "sed -i -E 's/[[:space:]]+$//' modules/bar/BarContent.qml";
    patches = [ ../../patches/ambxst-minimal-bar.patch ];
  };

  ambxstPackage = inputs.ambxst.packages.${system}.default.overrideAttrs (old: {
    postBuild = (old.postBuild or "") + ''
      cp "$out/bin/ambxst" "$out/bin/ambxst-real"
      sed -i '/export AMBXST_SHELL=/c\\    export AMBXST_SHELL="${patchedShell}"' "$out/bin/ambxst-real"
      rm "$out/bin/ambxst"
      mv "$out/bin/ambxst-real" "$out/bin/ambxst"
    '';
  });
in
{
  imports = [ inputs.ambxst.nixosModules.default ];

  # Upstream's NixOS module installs Ambxst, axctl, its fonts, and the
  # services it needs (NetworkManager, UPower, power profiles, and recording).
  programs.ambxst.enable = true;
  programs.ambxst.package = ambxstPackage;
}

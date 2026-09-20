{ inputs, pkgs, ... }:

let
  heliumInlineTranslator = pkgs.stdenvNoCC.mkDerivation {
    pname = "helium-inline-translator";
    version = "1.1.1-c95e7b6";

    src = pkgs.fetchFromGitHub {
      owner = "wesleymartinsDV";
      repo = "helium-inline-translator";
      rev = "c95e7b672a5b37e9c2ea98578ee6f4994071f4c5";
      hash = "sha256-GHlmm4j0fPrMOTrcsqvUaTe6JpF2qKIa1L4Q5mx8Knk=";
    };

    postPatch = ''
      substituteInPlace src/content.js \
        --replace-fail 'pressedKey === "shift+alt+q"' 'pressedKey === "ctrl+shift+z"' \
        --replace-fail 'Shift+Alt+Q' 'Ctrl+Shift+Z'
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r ./* $out/
      runHook postInstall
    '';
  };
in

{
  imports = [ inputs.helium-browser.nixosModules.default ];

  programs.helium = {
    enable = true;
    flags = [
      "--ozone-platform-hint=auto"
      "--load-extension=${heliumInlineTranslator}"
    ];
    policies = {
      BrowserSignin = 0;
      SpellcheckEnabled = true;
      SpellcheckLanguage = [
        "en-US"
        "ru"
      ];
    };
  };
}

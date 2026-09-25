{ inputs, pkgs, ... }:

let
  heliumInlineTranslator = pkgs.stdenvNoCC.mkDerivation {
    pname = "helium-inline-translator";
    version = "0.3.1-f743566";

    src = pkgs.fetchFromGitHub {
      owner = "WINEEL";
      repo = "chrome-inline-translate";
      rev = "f7435667a92bf6dc473fc5732eb424c9a79b9255";
      hash = "sha256-TLOQSl9nUUNyuHdUpfAjNlg8O+jXrLuyFuRd6mFU7kM=";
    };

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

  environment.etc."xdg/applications/helium.desktop".text = ''
    [Desktop Entry]
    Name=Helium
    Comment=Private, fast, and honest web browser
    Exec=/run/current-system/sw/bin/helium --load-extension=${heliumInlineTranslator} %U
    Terminal=false
    Type=Application
    Icon=helium
    Categories=Network;WebBrowser;
    MimeType=text/html;application/xhtml+xml;application/xml;application/pdf;x-scheme-handler/http;x-scheme-handler/https;
  '';

  programs.helium = {
    enable = true;
    flags = [
      "--ozone-platform-hint=auto"
      "--load-extension=${heliumInlineTranslator}"
    ];
    policies = {
      BrowserSignin = 0;
      RestoreOnStartup = 1;
      SpellcheckEnabled = true;
      SpellcheckLanguage = [
        "en-US"
        "ru"
      ];
      ManagedBookmarks = [
        {
          toplevel_name = "Helium";
          children = [
            {
              name = "cookies";
              url = "helium://settings/content/all";
            }
          ];
        }
      ];
    };
  };
}

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

    nativeBuildInputs = [ pkgs.python3 ];

    postPatch = ''
      substituteInPlace src/content.js \
        --replace-fail 'pressedKey === "shift+alt+q"' 'pressedKey === "ctrl+shift+z"' \
        --replace-fail 'Shift+Alt+Q' 'Ctrl+Shift+Z'

      python -c 'import json; from pathlib import Path; p=Path("manifest.json"); d=json.loads(p.read_text()); d["host_permissions"]=["https://translate.googleapis.com/*"]; d["commands"]={"translate-selection":{"suggested_key":{"default":"Ctrl+Shift+Z"},"description":"Translate selected text"}}; p.write_text(json.dumps(d, indent=2)+"\n"); p=Path("src/background.js"); s=p.read_text(); s=s.replace("chrome.runtime.onMessage.addListener", "chrome.commands.onCommand.addListener(async (command) => { if (command !== \"translate-selection\") return; const [tab] = await chrome.tabs.query({ active: true, currentWindow: true }); if (tab?.id) chrome.tabs.sendMessage(tab.id, { action: \"translate-selection\" }); });"+chr(10)+"chrome.runtime.onMessage.addListener", 1); p.write_text(s)'
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

  environment.etc."xdg/applications/helium.desktop".text = ''
    [Desktop Entry]
    Name=Helium
    Comment=Private, fast, and honest web browser
    Exec=/run/current-system/sw/bin/helium %U
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
    };
  };
}

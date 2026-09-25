{ inputs, pkgs, ... }:

let
  popupContent = pkgs.writeText "helium-inline-translator-content.js" ''
    async function handleSelectionTranslation() {
      const selection = window.getSelection();
      if (!selection || !selection.rangeCount || selection.isCollapsed) return;

      const range = selection.getRangeAt(0).cloneRange();
      const text = selection.toString().trim();
      if (!text) return;

      removeSelectionBubble();
      const bubble = createSelectionBubble(range);
      bubble.output.textContent = "Translating…";

      try {
        const response = await chrome.runtime.sendMessage({ action: "getTranslation", text });
        bubble.output.textContent = response?.translatedText || "Translation failed.";
      } catch (error) {
        console.error("Helium Inline Translator: selection translation failed", error);
        bubble.output.textContent = "Translation failed.";
      }
    }

    function removeSelectionBubble() {
      selectionBubble?.remove();
      selectionBubble = null;
    }

    function createSelectionBubble(range) {
      const bubble = document.createElement("div");
      const output = document.createElement("div");
      const copy = document.createElement("button");
      const close = document.createElement("button");
      const rect = range.getBoundingClientRect();

      bubble.id = "helium-translation-bubble";
      bubble.style.cssText = "position:absolute;z-index:2147483647;max-width:420px;min-width:180px;padding:10px;border:1px solid #bbb;border-radius:8px;background:#fff;color:#222;box-shadow:0 4px 18px #0003;font:14px sans-serif;line-height:1.4";
      output.style.cssText = "max-height:220px;overflow:auto;white-space:pre-wrap";
      copy.textContent = "Copy";
      close.textContent = "×";
      copy.style.cssText = close.style.cssText = "margin:8px 6px 0 0;border:1px solid #ccc;border-radius:4px;background:#fff;cursor:pointer";
      copy.onclick = () => navigator.clipboard.writeText(output.textContent);
      close.onclick = removeSelectionBubble;
      bubble.append(output, document.createElement("br"), copy, close);
      document.body.appendChild(bubble);
      bubble.style.left = `''${Math.max(8, Math.min(window.scrollX + rect.left, window.scrollX + document.documentElement.clientWidth - 428))}px`;
      bubble.style.top = `''${window.scrollY + rect.bottom + 8}px`;
      selectionBubble = bubble;
      return { output };
    }

    document.addEventListener("mousedown", (event) => {
      if (selectionBubble && !selectionBubble.contains(event.target)) removeSelectionBubble();
    }, true);

  '';

  popupPatch = pkgs.writeText "helium-inline-translator-popup.py" ''
    import json
    import re
    from pathlib import Path

    manifest = Path("manifest.json")
    data = json.loads(manifest.read_text())
    data["host_permissions"] = ["https://translate.googleapis.com/*"]
    data["commands"] = {"translate-selection": {
        "suggested_key": {"default": "Ctrl+Shift+Z"},
        "description": "Translate selected text",
    }}
    manifest.write_text(json.dumps(data, indent=2) + "\n")

    path = Path("src/content.js")
    source = path.read_text()
    source = source.replace(
        "// Global state for selection translation\n"
        "let selectionOriginals = new Map();\n"
        "let lastTranslatedNodes = [];\n"
        "let isSelectionTranslated = false;",
        "let selectionBubble = null;",
    )
    source = source.replace(
        "  if (request.action === \"translate-selection\") {\n"
        "    if (isSelectionTranslated) {\n"
        "      revertSelectionTranslation();\n"
        "    } else {\n"
        "      handleSelectionTranslation();\n"
        "    }",
        "  if (request.action === \"translate-selection\") {\n"
        "    handleSelectionTranslation();",
    )
    source = source.replace(
        "    if (isSelectionTranslated) {\n"
        "      console.log(\"Helium Inline Translator: Reverting selection translation\");\n"
        "      revertSelectionTranslation();\n"
        "    } else if (selection && !selection.isCollapsed) {",
        "    if (selection && !selection.isCollapsed) {",
    )
    replacement = Path("${popupContent}").read_text()
    source = re.sub(
        r"async function handleSelectionTranslation\(\) \{.*?\n\}\n\n(?=function collectTextNodesFromRange)",
        replacement,
        source,
        count=1,
        flags=re.S,
    )
    path.write_text(source)
  '';

  heliumInlineTranslator = pkgs.stdenvNoCC.mkDerivation {
    pname = "helium-inline-translator";
    version = "1.1.1-c95e7b6-popup";

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

            substituteInPlace ui/popup.html \
              --replace-fail 'Shift + Alt + Q' 'Ctrl + Shift + Z'

      python -c 'exec("\n".join(line[4:] if line.startswith("    ") else line for line in open("${popupPatch}")))'
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

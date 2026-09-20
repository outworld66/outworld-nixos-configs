{ inputs, ... }:

{
  imports = [ inputs.helium-browser.nixosModules.default ];

  programs.helium = {
    enable = true;
    flags = [
      "--ozone-platform-hint=auto"
      "--enable-features=DesktopPartialTranslate"
    ];
    policies = {
      BrowserSignin = 0;
      TranslateEnabled = true;
      SpellcheckEnabled = true;
      SpellcheckLanguage = [
        "en-US"
        "ru"
      ];
    };
  };
}

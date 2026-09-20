{ inputs, ... }:

{
  imports = [ inputs.helium-browser.nixosModules.default ];

  programs.helium = {
    enable = true;
    flags = [ "--ozone-platform-hint=auto" ];
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

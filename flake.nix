{
  description = "My system configuration";

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nirinit = {
      url = "github:amaanq/nirinit";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vicinae-extensions = {
      url = "github:vicinaehq/extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms = {
      url = "git+https://github.com/AvengeMedia/DankMaterialShell.git?ref=stable&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dgop = {
      url = "github:AvengeMedia/dgop";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    outworld-packages = {
      url = "github:outworld66/outworld-nixos-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The bundled implementation exports empty settings. Override this input
    # with a private companion flake to add identity, hardware and local
    # modules without making that repository a prerequisite.
    private = {
      url = "path:./defaults/private";
    };

  };

  outputs =
    {
      nixpkgs,
      ...
    }@inputs:
    let
      # Safe defaults keep the public flake evaluable without a private
      # identity repository. Real machines override these through makeSystem.
      system = "x86_64-linux";
      homeStateVersion = "26.05";
      allowedUnfreePackages = [
        "google-chrome"
        "kaspersky-ksc-agent"
        "obsidian"
        "steam"
        "steam-unwrapped"
      ];

      privateConfig = inputs.private.config or { };
      privateHosts = inputs.private.hostConfigurations or { };
      privateSpecialArgs = inputs.private.specialArgs or { };
      privateSystemUser = privateConfig.systemUser or { };
      privateDefaultGitUser = (privateConfig.gitUsers or { }).default or { };
      identity = rec {
        user = privateSystemUser.name or (privateConfig.user or "nixos");
        group = privateSystemUser.group or (privateConfig.group or "users");
        gitUsername = privateDefaultGitUser.name or (privateConfig.gitUsername or user);
        gitMail = privateDefaultGitUser.email or (privateConfig.gitMail or "${user}@example.invalid");
        configDirectory = privateConfig.configDirectory or "/home/${user}/nix";
        activationFlake = privateConfig.activationFlake or configDirectory;
      };

      # Host-specific values used to generate nixosConfigurations below.
      hosts = [
        {
          hostname = "tpx13";
          stateVersion = "26.05";
          hostModule = ./hosts/tpx13/configuration.nix;
          hardwareModule = ./hosts/evaluation-hardware.nix;
        }
        {
          hostname = "majesty";
          stateVersion = "25.11";
          hostModule = ./hosts/majesty/configuration.nix;
          hardwareModule = ./hosts/evaluation-hardware.nix;
        }
      ];

      # Package set used by formatter, checks, apps and the development shell.
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) allowedUnfreePackages;
      };

      # One formatter/linter configuration shared by `nix fmt` and flake checks.
      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs = {
          deadnix.enable = true;
          nixfmt.enable = true;
          statix.enable = true;
        };
        settings.global.excludes = [
          ".direnv/**"
          ".git/**"
          ".omx/**"
          "home-manager/dotfiles/**"
          "hosts/*/hardware-configuration.nix"
        ];
      };

      # Build a NixOS configuration from one entry in `hosts`.
      makeSystem =
        {
          hostname,
          stateVersion,
          hostModule,
          hardwareModule ? null,
          user ? "nixos",
          group ? "users",
          gitUsername ? user,
          gitMail ? "${user}@example.invalid",
          configDirectory ? "/home/${user}/nix",
          activationFlake ? configDirectory,
          extraModules ? [ ],
          extraHomeModules ? [ ],
          extraSpecialArgs ? { },
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              inputs
              system
              stateVersion
              homeStateVersion
              hostname
              user
              gitUsername
              gitMail
              allowedUnfreePackages
              group
              configDirectory
              activationFlake
              extraHomeModules
              extraSpecialArgs
              ;
          }
          // extraSpecialArgs;

          modules = [
            {
              nixpkgs.overlays = [ (_final: _previous: inputs.outworld-packages.packages.${system}) ];
            }
            ./nixos/modules
            hostModule
          ]
          ++ nixpkgs.lib.optional (hardwareModule != null) hardwareModule
          ++ extraModules;
        };

      customPackages = inputs.outworld-packages.packages.${system};

      # Entry point used by both `nix run .#check` and Taskfile.yml.
      checkScript = pkgs.writeShellApplication {
        name = "check";
        runtimeInputs = [
          pkgs.git
          pkgs.gitleaks
          pkgs.nix
        ];
        text = ''
          gitleaks dir --no-banner --redact .
          nix flake check --print-build-logs "$@"
          git diff --check
        '';
      };

      # Opt-in installer for the repository's versioned Git hooks.
      installHooksScript = pkgs.writeShellApplication {
        name = "install-hooks";
        runtimeInputs = [ pkgs.git ];
        text = ''
          repository_root="$(git rev-parse --show-toplevel)"
          git -C "$repository_root" config --local core.hooksPath .githooks
          echo "Local CI hooks enabled for $repository_root"
        '';
      };

    in
    {
      lib = {
        inherit makeSystem;
      };

      nixosModules = {
        default = ./nixos/modules;
        tpx13 = ./hosts/tpx13/configuration.nix;
        majesty = ./hosts/majesty/configuration.nix;
      };
      homeModules.default = ./home-manager/modules;

      # Generate tpx13 and majesty from the declarative host list.
      nixosConfigurations = nixpkgs.lib.foldl' (
        configs: host:
        let
          privateHost = privateHosts.${host.hostname} or { };
        in
        configs
        // {
          "${host.hostname}" = makeSystem {
            inherit (host)
              hostname
              stateVersion
              hostModule
              ;
            inherit (identity)
              user
              group
              gitUsername
              gitMail
              configDirectory
              activationFlake
              ;
            hardwareModule = privateHost.hardwareModule or host.hardwareModule;
            extraModules = privateHost.extraModules or [ ];
            extraHomeModules = privateHost.extraHomeModules or [ ];
            extraSpecialArgs = privateSpecialArgs // (privateHost.extraSpecialArgs or { });
          };
        }
      ) { } hosts;

      # Re-exported package-library packages are also build checks.
      packages.${system} = customPackages // {
        check = checkScript;
        default = checkScript;
      };

      formatter.${system} = treefmtEval.config.build.wrapper;

      # `nix develop` provides the task runner and safe NixOS rebuild frontend.
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [
          pkgs.go-task
          pkgs.gitleaks
          pkgs.nh
        ];
      };

      # Check formatting, build package-library packages and evaluate both systems.
      checks.${system} =
        customPackages
        // {
          formatting = treefmtEval.config.build.check inputs.self;
        }
        // nixpkgs.lib.mapAttrs' (
          hostname: configuration:
          nixpkgs.lib.nameValuePair "nixos-${hostname}" configuration.config.system.build.toplevel
        ) inputs.self.nixosConfigurations;

      # Runnable flake commands; the default app is the local CI.
      apps.${system} = {
        check = {
          type = "app";
          program = "${checkScript}/bin/check";
          meta.description = "Run all local CI checks";
        };
        install-hooks = {
          type = "app";
          program = "${installHooksScript}/bin/install-hooks";
          meta.description = "Enable versioned Git hooks for this clone";
        };
        default = inputs.self.apps.${system}.check;
      };
    };
}

{
  description = "A simple ruby app demo";

  nixConfig = {
    extra-substituters = "https://nixpkgs-ruby.cachix.org";
    extra-trusted-public-keys = "nixpkgs-ruby.cachix.org-1:vrcdi50fTolOxWCZZkw0jakOnUI1T19oYJ+PRYdK4SM=";
  };

  inputs = {
    nixpkgs.url = "nixpkgs";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    ruby-nix.url = "github:inscapist/ruby-nix";
    # a fork that supports platform dependant gem
    bundix = {
      url = "github:inscapist/bundix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fu.url = "github:numtide/flake-utils";
    bob-ruby.url = "path:/home/matt/projects/nixpkgs-ruby";
    bob-ruby.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-master,
      fu,
      ruby-nix,
      bundix,
      bob-ruby,
    }:
    with fu.lib;
    eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ bob-ruby.overlays.default ];
        };
        rubyNix = ruby-nix.lib pkgs;
        pkgsUnstable = import nixpkgs-unstable {
          inherit system;
        };
        pkgsMaster = import nixpkgs-master {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
            vulkanSupport = true;
          };
        };

        # TODO generate gemset.nix with bundix
        gemset = if builtins.pathExists ./gemset.nix then import ./gemset.nix else { };

        # If you want to override gem build config, see
        #   https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/ruby-modules/gem-config/default.nix
        gemConfig = { };

        # See available versions here: https://github.com/bobvanderlinden/nixpkgs-ruby/blob/master/ruby/versions.json
        ruby = pkgs."ruby-nightly";

        # Running bundix would regenerate `gemset.nix`
        bundixcli = bundix.packages.${system}.default;

        # Use these instead of the original `bundle <mutate>` commands
        bundleLock = pkgs.writeShellScriptBin "bundle-lock" ''
          export BUNDLE_PATH=vendor/bundle
          bundle lock
        '';
        bundleUpdate = pkgs.writeShellScriptBin "bundle-update" ''
          export BUNDLE_PATH=vendor/bundle
          bundle lock --update
        '';
        gitBug = import ./git-bug.nix {
          inherit pkgs;
        };
      in
      rec {
        inherit
          (rubyNix {
            inherit gemset ruby;
            name = "LogShout";
            gemConfig = pkgs.defaultGemConfig // gemConfig;
          })
          env
          ;

        devShells = rec {
          default = dev;
          dev = pkgs.mkShell {
            buildInputs = [
              env
              ruby
              bundixcli
              bundleLock
              bundleUpdate
              gitBug
            ]
            ++ (with pkgs; [
              nixfmt
              nodejs
              chromium
              firefox
              python3
              python3Packages.uv
              libyaml
              glib
              nss
              atk
              at-spi2-atk
              cups
              libdrm
              xorg.libXcomposite
              xorg.libXdamage
              xorg.libXfixes
              xorg.libXrandr
              mesa
              alsa-lib
              pkgsMaster.claude-code
              watchman
              llama-cpp
            ]);
          };
        };
      }
    );
}

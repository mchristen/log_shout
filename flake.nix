{
  description = "A simple ruby app demo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ruby-nix.url = "github:inscapist/ruby-nix";
    ruby-nix.inputs.nixpkgs.follows = "nixpkgs";
    # ruby-nix requires this fork for platform-dependent gems.
    bundix = {
      url = "github:inscapist/bundix/main";
      flake = false;
    };
    fu.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      fu,
      ruby-nix,
      bundix,
    }:
    with fu.lib;
    eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        rubyNix = ruby-nix.lib pkgs;
        # TODO generate gemset.nix with bundix
        gemset = if builtins.pathExists ./gemset.nix then import ./gemset.nix else { };

        # If you want to override gem build config, see
        #   https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/ruby-modules/gem-config/default.nix
        gemConfig = { };

        # Ruby 4.0 includes the Ractor::Port API previously used from nightly.
        ruby = pkgs.ruby_4_0;

        # Running bundix would regenerate `gemset.nix`
        # Build the fork with our Ruby; its flake hardcodes an older Ruby.
        bundixcli = pkgs.callPackage "${bundix}/default.nix" {
          inherit pkgs ruby;
          bundler = pkgs.bundler.override { inherit ruby; };
        };

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
              libxcomposite
              libxdamage
              libxfixes
              libxrandr
              mesa
              alsa-lib
              claude-code
              watchman
              llama-cpp
            ]);
          };
        };
      }
    );
}

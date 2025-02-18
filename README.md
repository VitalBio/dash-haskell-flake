# Dash Haskell Flake

This repository is for building [Dash](https://kapeli.com/dash) docsets using Nix [Haskell
Flakes](https://flake.parts/options/haskell-flake).

I tried to use existing Haskell packages to do this (see [Prior Art](#prior-art)) but couldn't since
they are out of date. Rather than trying to upgrade them, I used the Dash-recommended
[Dashing](https://github.com/technosophos/dashing#readme) package to generate docs, and then indexed
them with CSS selectors:

```json
"selectors": {
  "div#package-header": "Package",
  "div#module-header p": "Module",
  "p.src a[id^=t]": "Type",
  "td.src a[id^=v]": "Constructor",
  "p.src a[id^=v]": "Function"
},
```

## Usage

```nix
{
  inputs = {
    flake-parts.follows = "vital-nix/flake-parts";
    haskell-flake.url = "github:srid/haskell-flake";
    nixpkgs.url = "nixpkgs/release-23.11";
    dash-haskell.url = "git+ssh://git@github.com/VitalBio/dash-haskell-flake.git?ref=main";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.haskell-flake.flakeModule
        inputs.dash-haskell.flakeModule
      ];
      perSystem = {
        config,
        pkgs,
        ...
      }: {
        haskellProjects.default = {
          ...
        };
        dashHaskell = {
          name = "My Project";
          package = "my-project";
          externalUrl = "https://github.com/my-org/my-project";
          version = "1.0";
          mkDocsetUrl = pkgs.writeShellScript "mk-docset-url" ''
            echo "https://hydra.company.domain$(sed 's/nix\/store/nix-store/' <<< $1)"
          '';
          haskellProject = "default";
        };
        packages = rec {
          inherit (config.dashHaskell.outputs.default) haddock docset;
        };
      };
    };
```

## Prior Art

* https://github.com/jfeltz/dash-haskell
* https://github.com/philopon/haddocset

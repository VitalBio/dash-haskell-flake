{ config, self, pkgs, lib, flake-parts-lib, ... }:
let
  inherit (flake-parts-lib)
    mkPerSystemOption;
  inherit (lib)
    mkOption
    types;
in
{
  options.perSystem = mkPerSystemOption ({ config, self', pkgs, ... }: {
    options.dashHaskell = {
      name = mkOption {
        description = "Human readable name.";
        example = "My Package";
        type = types.str;
      };
      package = mkOption {
        description = "Machine readable name.";
        example = "my-package";
        type = types.str;
      };
      externalUrl = mkOption {
        description = "External link for clients to view source; typically a link to a git repository.";
        example = "https://github.com/myorg/my-package";
        default = "";
        type = types.str;
      };
      version = mkOption {
        description = "Docset version.";
        example = "1.0";
        default = "1.0";
        type = types.str;
      };
      mkDocsetUrl = mkOption {
        description = "Script which accepts a nix store path and outputs a URL to embed in the feed.xml file.";
        type = types.path;
      };
      haskellProject = mkOption {
        description = "Name of Haskell project in haskell flake.";
        example = "default";
        default = "default";
        type = types.str;
      };
      outputs = mkOption {
        description = "Doc outputs.";
        type = types.attrsOf (types.submodule {
          options = {
            haddock = mkOption {
              description = "Haddock HTML";
              type = types.package;
            };
            docset = mkOption {
              description = "Dash docset and feed.xml";
              type = types.package;
            };
          };
        });
      };
    };

    config =
      let
        name = config.dashHaskell.name;
        package = config.dashHaskell.package;
        externalUrl = config.dashHaskell.externalUrl;
        version = config.dashHaskell.version;
        mkDocsetUrl = config.dashHaskell.mkDocsetUrl;
        haskellProject = config.haskellProjects.${config.dashHaskell.haskellProject};
        ghc = haskellProject.basePackages.ghc;
        haskellPkgs = haskellProject.outputs.packages;

        haddock =
          let
            ghcDocLibDir = ghc.doc + "/share/doc/ghc*/html/libraries";

            relativizeScript = pkgs.writeShellScript "relativize-haddock-refs.sh" ''
              find $2 -type f -a \( -name \*.json -o -name \*.html \) -print0 | while IFS= read -r -d $'\0' f; do
                if ! grep -q nix/store "$f"; then
                  continue
                fi

                echo " $f"
                chmod +w "$f"
                sed -e "s@file:///nix/store/[^/]*/share/doc@$1@g"  < "$f" > "$NIX_BUILD_TOP/tmp"
                cp "$NIX_BUILD_TOP/tmp" "$f"
              done
            '';

            prologue = pkgs.writeText "prologue.txt" ''
              This index includes all packages local to or depended upon by ${package}.
            '';

            docPackages = lib.closePropagation
              (map (n: haskellPkgs.${n}.package.doc) (lib.attrNames haskellPkgs));

            builtinDocs = pkgs.stdenv.mkDerivation {
              name = "ghc-haddock-rel";
              unpackPhase = "true";
              buildCommand = ''
                mkdir "$out"
                for docdir in ${ghcDocLibDir}"/"*; do
                  name="$(basename "$docdir")"
                  if [[ -d "$docdir" ]]; then
                    cp -r "$docdir" "$out/$name"
                    ${relativizeScript} ".." "$out/$name"
                  fi
                done
              '';
            };

            importedDocs = lib.mapAttrs
              (n: d: pkgs.stdenv.mkDerivation {
                name = "${n}-haddock-rel";
                unpackPhase = "true";
                buildCommand = ''
                  mkdir "$out"
                  if [[ -d "${d}" ]]; then
                    cp -r "${d}" "$out/${n}"
                    ${relativizeScript} "../.." "$out/${n}"
                  fi
                '';
              })

              # make an attrset because docPackages might include duplicates
              (lib.listToAttrs (
                lib.filter (nv: nv != null) (
                  map
                    (p:
                      let
                        haddockDir = if p ? haddockDir then p.haddockDir p else null;
                      in
                        if haddockDir == null then null else {
                          name = p.name;
                          value = haddockDir;
                        }
                    )
                    docPackages
                )
              ));

          in pkgs.stdenv.mkDerivation {
            name = "${package}-haddock";
            buildInputs = [ghc pkgs.zip];
            unpackPhase = "true";
            passAsFile = ["buildCommand"];
            buildCommand = ''
              mkdir -p "$out/share/doc"

              ifaces=""

              echo "copying builtin docs"
              mkdir -p "$out/share/doc/ghc/html/libraries"
              for srcdir in "${builtinDocs}"/*; do
                pkgver="$(basename "$srcdir")"
                echo "  $pkgver"
                outdir="$out/share/doc/ghc/html/libraries/$pkgver"
                cp -r "$srcdir" "$outdir"
                iface=($outdir/*.haddock)
                echo "    $iface"
                ifaces="$ifaces --read-interface=$pkgver,$iface"
              done

              echo "copying imported haddocks"
              ${
                lib.concatMapStringsSep "\n"
                  (pkg: ''
                    for srcdir in "${pkg}/"*; do
                      pkgver="$(basename "$srcdir")"
                      echo "  $pkgver"
                      outdir="$out/share/doc/$pkgver"
                      mkdir -p "$outdir"
                      cp -r "$srcdir" "$outdir/html"
                      iface=($outdir/html/*.haddock)
                      echo "    $iface"
                      ifaces="$ifaces --read-interface=$pkgver/html,$iface"
                    done
                  '')
                  (lib.attrValues importedDocs)
              }

              echo "generating index"

              cd "$out/share/doc"

              # adapted from GHC's gen_contents_index

              ${ghc}/bin/haddock --gen-index --gen-contents -o . \
                   -t "${package}-haddock" \
                   -p "${prologue}" \
                   $ifaces

              echo "finishing up"
              mkdir "$out"/nix-support
              echo "doc manual $out/share/doc" >> $out/nix-support/hydra-build-products
            '';
          };

        dashingConfig = pkgs.writeText "${package}-dashing-config.json" ''
          {
            "name": "${name}",
            "package": "${package}",
            "index": "index.html",
            "selectors": {
              "div#package-header": "Package",
              "div#module-header": "Module",
              "p.src a[id^=t]": "Type",
              "td.src a[id^=v]": "Constructor",
              "p.src a[id^=v]": "Function"
            },
            "ignore": [],
            "icon32x32": "",
            "allowJS": true,
            "ExternalURL": "${externalUrl}"
          }
        '';

        docset = pkgs.stdenv.mkDerivation {
          name = "${package}-dash-docset";
          buildInputs = [pkgs.dashing];
          src = haddock;
          phases = [
            "unpackPhase"
            "buildPhase"
            "installPhase"
          ];
          unpackPhase = ''
            cp -r $src/share/doc/* .
            rm doc-index*
          '';
          buildPhase = ''
            dashing build --config ${dashingConfig}
          '';
          installPhase = ''
            mkdir -p $out
            mkdir $out/nix-support
            tar -cvzf $out/${package}-docset.tgz ${package}.docset
            echo "<entry><version>${version}</version><url>$(${mkDocsetUrl} $out/${package}-docset.tgz)</url></entry>" > $out/feed.xml
            echo "doc dist $out/${package}-docset.tgz" >> $out/nix-support/hydra-build-products
            echo "doc ${package}-docset $out/feed.xml" >> $out/nix-support/hydra-build-products
          '';
        };
      in {
        haskellProjects.${config.dashHaskell.haskellProject}.defaults.settings.defined.haddock = true;

        dashHaskell.outputs.${config.dashHaskell.haskellProject} = {
          inherit haddock docset;
        };
      };
  });
}

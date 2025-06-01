{
  inputs = {
    systems.url = "github:nix-systems/default";
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "nixpkgs/nixos-25.05";

    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      perSystem =
        { pkgs, system, ... }:
        let
          treefmt =
            (inputs.treefmt-nix.lib.evalModule pkgs {
              projectRootFile = "flake.lock";
              programs = {
                mdformat = {
                  enable = true;
                  settings.wrap = 80;
                };
                nixfmt.enable = true;
              };
            }).config.build.wrapper;

          pre-commit = inputs.pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks.treefmt = {
              enable = true;
              package = treefmt;
              pass_filenames = false;
            };
          };
        in
        {
          checks.pre-commit = pre-commit;
          formatter = treefmt;
          devShells.default = pkgs.mkShellNoCC {
            inherit (pre-commit) shellHook;
            packages = with pkgs; [
              git
              marksman
              nil
            ];
          };
          packages =
            let
              HTMLToEPUBManual =
                {
                  outName,
                  title,
                  srcDir,
                  targetFileName,
                }:
                pkgs.runCommand outName { nativeBuildInputs = [ pkgs.pandoc ]; } ''
                  tmpdir=$(mktemp -d)
                  tmpfile=$(mktemp --tmpdir=$tmpdir --suffix='.html')

                  cp -r ${srcDir}/* $tmpdir
                  find $tmpdir -type d -exec chmod 755 {} +
                  find $tmpdir -type f -exec chmod 644 {} +
                  # For some reason, the built manual package references
                  # `build/source/out` instead of the file in the same
                  # directory. There surely is a good reason for this,
                  # but these packages are hacky as it is, so this is
                  # fine.
                  sed -i \
                    's,/build/source/out/index-redirects.js,./index-redirects.js,g' \
                    $tmpdir/*.html

                  cd $tmpdir
                  # NOTE: It would be nice to generate a proper table of
                  #       contents, but Pandoc does not like the way that
                  #       the headers are structured in the manuals, so it
                  #       ends up just creating a single top-level section,
                  #       which is useless. To do this right, it would
                  #       require doing some processing on the HTML to get
                  #       it "right" or working with the actual Markdown files
                  #       that are what the HTML itself is generated from.
                  #       That would involve a lot more work for very little
                  #       benefit, so that's omitted right now. Those efforts
                  #       would be better suited for implementing proper EPUB
                  #       support for the `nixos-render-docs` toolchain instead.
                  pandoc ${targetFileName} \
                    --verbose \
                    --metadata title='${title}' \
                    -o $out
                '';

              manuals = {
                nixosEPUBManual = HTMLToEPUBManual {
                  outName = "nixos-manual.epub";
                  title = "NixOS Manual";
                  srcDir = "${inputs.nixpkgs.htmlDocs.nixosManual.${system}}/share/doc/nixos";
                  targetFileName = "index.html";
                };
                nixpkgsEPUBManual = HTMLToEPUBManual {
                  outName = "nixpkgs-manual.epub";
                  title = "Nixpkgs Reference Manual";
                  srcDir = "${inputs.nixpkgs.htmlDocs.nixpkgsManual.${system}}/share/doc/nixpkgs";
                  targetFileName = "manual.html";
                };
              };
            in
            {
              default = pkgs.linkFarm "nix-manuals-epub" (
                builtins.map (m: {
                  inherit (m) name;
                  path = m;
                }) (builtins.attrValues manuals)
              );
            }
            // manuals;
        };
    };
}

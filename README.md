# nur-packages

**My personal [NUR](https://github.com/nix-community/NUR) repository**

The default dev shell provides nixfmt-rs and statix. Format Nix files with `nix develop -c nixfmt .`. Run `nix develop -c bash -c 'nixfmt --check . && statix check .'` for static checks and `nix flake check --no-build` to check flake evaluation on the current system.

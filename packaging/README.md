# Packaging

UOLT is **x86_64 only** (Linux and Intel macOS). arm64 is planned; do not ship
these on Apple Silicon or arm64 Linux yet. Every binary installs as
`uolt-<name>` so a package never silently shadows the system coreutils.

The release tarball for a tag `vX.Y.Z` is
`https://github.com/thooams/uolt/archive/refs/tags/vX.Y.Z.tar.gz`. Get its hash
with `curl -sL <url> | sha256sum` and update the files below on every release.

## Nix (in-repo flake)

Already wired up at the repo root:

```sh
nix run github:thooams/uolt/v0.1.0 -- --help   # or any uolt-* via nix build
nix build github:thooams/uolt#default          # result/bin/uolt-*
```

## Homebrew tap (`homebrew/uolt.rb`)

1. Create a repo `github.com/thooams/homebrew-tap`.
2. Copy `homebrew/uolt.rb` to `Formula/uolt.rb` there and push.
3. Users: `brew install thooams/tap/uolt`.

Update `url` + `sha256` per release. (Homebrew core has a notability bar; a tap
has none - start here.)

## AUR (`aur/PKGBUILD`)

1. Clone the AUR package repo: `git clone ssh://aur@aur.archlinux.org/uolt.git`.
2. Copy `aur/PKGBUILD` and `aur/.SRCINFO` in (regenerate the latter with
   `makepkg --printsrcinfo > .SRCINFO` after editing the PKGBUILD).
3. `git commit` and push to the AUR.
4. Users: `yay -S uolt` (or any AUR helper).

Bump `pkgver`, refresh `sha256sums`, and regenerate `.SRCINFO` per release.

## Higher-gatekeeping repos (later)

Debian/Fedora/nixpkgs/Homebrew-core expect notability and a maintenance
commitment. Pursue them once the project has traction, not before launch.

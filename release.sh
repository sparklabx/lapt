#!/usr/bin/env bash
# Package bin/+lib/ and publish as a GitHub release asset.
# usage: ./release.sh <version>   (e.g. ./release.sh v0.1.0)
set -euo pipefail

version=${1:?usage: ./release.sh <version>}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tarball="lapt-${version}.tar.gz"

tar czf "$tarball" -C "$root" bin lib pkgenv
if gh release view "$version" >/dev/null 2>&1; then
  gh release upload "$version" "$tarball" --clobber
else
  gh release create "$version" "$tarball" --title "$version" --notes ""
fi
# gh release create attaches assets via create-as-draft -> upload -> publish;
# if that last publish call doesn't land, the release is left stuck in Draft.
gh release edit "$version" --draft=false
rm -f "$tarball"

#!/usr/bin/env bash
# smhub/setup.sh — pin-clone upstream Buildroot for the SMHub .ipk lane.
#
# Mirrors bsp/setup.sh: the tree is NOT committed, it is cloned here, pinned to
# an immutable upstream tag, and stays gitignored. Our inputs (defconfig,
# package override) live in smhub/ and build.sh injects them.
#
# WHY THIS TAG. The live unit reports Buildroot 2026.02-1281-g9407f694e5 - the
# vendor's own 1281 commits past tag 2026.02, which upstream does not have, so
# bit-identical reproduction is out. What matters is the ABI, and it did not
# move: glibc stayed 2.42 across the 1.0.2 OTA, and tag 2026.02 pins
# glibc 2.42-51-gcbf39c2 with GCC 15.2.0 available. Building at 2.42 runs on
# 2.42+; building on master (glibc 2.44) does not run there at all.
set -euo pipefail

SMHUB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TREE="${HOMEAGENT_SMHUB_BR:-$SMHUB_DIR/sdk}"
BR_URL="${BR_URL:-https://github.com/buildroot/buildroot.git}"
BR_TAG="${BR_TAG:-2026.02}"
# A local clone (~/repos/3rd/milkv/buildroot-master) is used as an object
# reference when present, so this costs no network for the history.
BR_REFERENCE="${BR_REFERENCE:-$HOME/repos/3rd/milkv/buildroot-master}"

if [ -d "$TREE/.git" ]; then
  echo "[smhub] tree exists: $TREE"
else
  ref_args=()
  if [ -d "$BR_REFERENCE/.git" ]; then
    echo "[smhub] using local reference: $BR_REFERENCE"
    ref_args=(--reference-if-able "$BR_REFERENCE" --dissociate)
  fi
  echo "[smhub] cloning Buildroot $BR_TAG -> $TREE"
  git clone --branch "$BR_TAG" --depth 1 "${ref_args[@]}" "$BR_URL" "$TREE"
fi

cd "$TREE"
HEAD_DESC="$(git describe --tags --always 2>/dev/null || echo unknown)"
echo "[smhub] tree at: $HEAD_DESC"

# An EXISTING tree is not automatically the right tree. Until 2026-09-08 this
# script only checked the glibc pin here, so any drifted HEAD would have passed
# and the README's "verifies the pin and stops" was an overstatement. Pin the
# commit itself. Note the ^{commit} peel: BR_TAG is an ANNOTATED tag, so bare
# `rev-parse 2026.02` yields the tag OBJECT sha, not the commit -- comparing
# the wrong one of those two is how a correct tree gets misread as drifted.
WANT_COMMIT="$(git rev-parse --verify --quiet "refs/tags/$BR_TAG^{commit}" || true)"
HAVE_COMMIT="$(git rev-parse HEAD)"
if [ -z "$WANT_COMMIT" ]; then
  echo "[smhub] ERROR: tag '$BR_TAG' not present in $TREE (shallow clone without tags?)." >&2
  echo "[smhub]        git -C $TREE fetch --tags --depth 1 origin tag $BR_TAG" >&2
  exit 1
fi
if [ "$HAVE_COMMIT" != "$WANT_COMMIT" ]; then
  echo "[smhub] ERROR: tree HEAD is not $BR_TAG." >&2
  echo "[smhub]        want $WANT_COMMIT ($BR_TAG)" >&2
  echo "[smhub]        have $HAVE_COMMIT" >&2
  echo "[smhub]        git -C $TREE fetch --tags && git -C $TREE checkout --detach $WANT_COMMIT" >&2
  exit 1
fi
echo "[smhub] commit pin OK: $HAVE_COMMIT ($BR_TAG)"

# build.sh injects our defconfig/recipe into this tree, so a dirty worktree is
# EXPECTED -- but only in those known paths. Anything else is an unrecorded
# local edit that would not survive a re-clone, i.e. not reproducible.
UNEXPECTED="$(git status --porcelain | grep -vE ' (configs/smhub-nano-riscv64_defconfig|package/domoticz/domoticz\.(mk|hash))$|^\?\? (\.config\.smhub-stamp|configs/smhub-nano-riscv64_defconfig|output/|dl/)' || true)"
if [ -n "$UNEXPECTED" ]; then
  echo "[smhub] WARNING: tree carries edits outside the injected inputs --" >&2
  echo "$UNEXPECTED" >&2
  echo "[smhub]        these will NOT reproduce from a fresh clone. Move them into smhub/." >&2
fi

# Fail loudly if the pin drifted: this tree's whole job is to be glibc 2.42.
GLIBC_PIN="$(sed -n 's/^GLIBC_VERSION = //p' package/glibc/glibc.mk)"
case "$GLIBC_PIN" in
  2.42*) echo "[smhub] glibc pin OK: $GLIBC_PIN" ;;
  *)     echo "[smhub] ERROR: glibc pin is '$GLIBC_PIN', expected 2.42* (device ABI)." >&2
         echo "[smhub] The SMHub unit runs glibc 2.42; a newer build will not start there." >&2
         exit 1 ;;
esac
echo "[smhub] python3 pin: $(sed -n 's/^PYTHON3_VERSION = //p' package/python3/python3.mk | head -1) (device 3.14.6, same 3.14 soname)"
echo "[smhub] next: ./smhub/build.sh"

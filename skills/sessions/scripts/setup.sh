#!/usr/bin/env sh
# cc-sessions dependency setup — installs ccsearch and jq (macOS & Linux).
# Idempotent: safe to re-run; skips anything already installed.
set -eu

have() { command -v "$1" >/dev/null 2>&1; }

ok=0
fail() { echo "ERROR: $1" >&2; ok=1; }

# --- ccsearch -----------------------------------------------------------
if have ccsearch; then
    echo "ccsearch: already installed ($(ccsearch --version))"
else
    echo "ccsearch: installing..."
    if have brew; then
        brew install madzarm/tap/ccsearch
    elif have curl; then
        # Official installer: static binary into ~/.local/bin, no sudo.
        curl -fsSL https://raw.githubusercontent.com/madzarm/ccsearch/master/install.sh | sh
        case ":${PATH}:" in
            *":${HOME}/.local/bin:"*) ;;
            *) echo "NOTE: add ~/.local/bin to your PATH (ccsearch was installed there)." ;;
        esac
    else
        fail "need brew or curl to install ccsearch — see https://github.com/madzarm/ccsearch#installation"
    fi
fi

# --- jq -----------------------------------------------------------------
if have jq; then
    echo "jq: already installed ($(jq --version))"
else
    echo "jq: installing..."
    if have brew; then
        brew install jq
    elif have apt-get; then
        sudo apt-get update -qq && sudo apt-get install -y jq
    elif have dnf; then
        sudo dnf install -y jq
    elif have pacman; then
        sudo pacman -S --noconfirm jq
    elif have apk; then
        sudo apk add jq
    else
        fail "no known package manager found — install jq manually: https://jqlang.org/download/"
    fi
fi

[ "$ok" -eq 0 ] || exit 1

# --- warm the index ------------------------------------------------------
# First run downloads a small local embedding model (~80MB) and indexes
# ~/.claude/projects. Doing it now keeps the first real search fast.
CCSEARCH="$(command -v ccsearch || true)"
[ -n "$CCSEARCH" ] || CCSEARCH="${HOME}/.local/bin/ccsearch"
if [ -x "$CCSEARCH" ]; then
    echo "Building search index (first run downloads a ~80MB local embedding model)..."
    "$CCSEARCH" index
fi

echo "cc-sessions setup complete."

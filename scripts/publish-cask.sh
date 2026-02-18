#!/usr/bin/env bash
set -euo pipefail

REPO="poltak/middleclick"
TAP_REPO_URL="git@github.com:poltak/homebrew-tap.git"
CASK_NAME="middleclick-poltak.rb"
DEFAULT_TAP_DIR="../homebrew-tap"

usage() {
  cat <<USAGE
Usage: $0 <tag> [--tap-dir <path>] [--no-push]

Examples:
  $0 v0.1.2
  $0 v0.1.2 --tap-dir /path/to/homebrew-tap
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

TAG=""
TAP_DIR="$DEFAULT_TAP_DIR"
PUSH=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tap-dir)
      TAP_DIR="${2:-}"
      shift 2
      ;;
    --no-push)
      PUSH=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$TAG" ]]; then
        TAG="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "Tag is required." >&2
  usage
  exit 1
fi

CASK_URL="https://github.com/${REPO}/releases/download/${TAG}/${CASK_NAME}"

if [[ ! -d "$TAP_DIR/.git" ]]; then
  echo "Cloning tap repo into $TAP_DIR"
  git clone "$TAP_REPO_URL" "$TAP_DIR"
fi

mkdir -p "$TAP_DIR/Casks"
TARGET_PATH="$TAP_DIR/Casks/${CASK_NAME}"

echo "Downloading $CASK_URL"
curl -fsSL "$CASK_URL" -o "$TARGET_PATH"

cd "$TAP_DIR"

if git diff --quiet -- "$TARGET_PATH" && git diff --cached --quiet -- "$TARGET_PATH"; then
  echo "No cask changes detected for ${TAG}. Nothing to commit."
  exit 0
fi

git add "$TARGET_PATH"
git commit -m "middleclick-poltak ${TAG}"

if [[ "$PUSH" == "true" ]]; then
  git push
  echo "Published cask update for ${TAG}."
else
  echo "Committed locally (push skipped): middleclick-poltak ${TAG}"
fi

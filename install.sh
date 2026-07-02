#!/usr/bin/env bash
set -euo pipefail

# ─── Formatting ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()  { echo -e "  ${YELLOW}!${NC}  $1"; }
step()  { echo -e "\n${BOLD}$1${NC}"; }
fail()  { echo -e "  ${RED}✗${NC}  $1"; exit 1; }
ask()   { read -r -p "     $1 [y/N] " _reply; [[ "$_reply" =~ ^[Yy]$ ]]; }
skip()  { warn "Skipped"; }

# Ensure a hook file is executable and not blocked by macOS quarantine.
make_executable() {
  local file="$1"
  chmod +x "$file"
  if [[ "$(uname)" == "Darwin" ]] && xattr "$file" 2>/dev/null | grep -q "com.apple.quarantine"; then
    xattr -d com.apple.quarantine "$file"
    info "Removed quarantine attribute from $(basename "$file")"
  fi
}

# Print a file's "# git-stuff-tag: <id>" line, if it has one. Lets us
# recognize "this is git-stuff's version" even after its contents have
# changed between versions, instead of relying on an exact byte match.
TAG_PATTERN='^# git-stuff-tag: '
file_tag() {
  [[ -f "$1" ]] || return 0
  head -n 5 "$1" | grep -m1 "$TAG_PATTERN" | sed -E "s/$TAG_PATTERN//"
}

# ─── Paths ───────────────────────────────────────────────────────────────────
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HOOKS_DIR="$HOME/.githooks"

echo ""
echo -e "${BOLD}git-stuff installer${NC}"
echo "  repo: $REPO_DIR"
echo "  hooks dir: $HOOKS_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Helper: install a symlink, with collision handling
#
# Usage: install_symlink <source> <target> [--no-collision-prompt]
#
# If the target already points to the source: no-op.
# If the target is a different symlink or an identical file: replace with symlink.
# If the target is a different file: prompt to rename it (with a suggested name),
#   then install the symlink. Pass --no-collision-prompt to skip the rename offer
#   and just warn instead.
# ─────────────────────────────────────────────────────────────────────────────
install_symlink() {
  local src="$1"
  local tgt="$2"
  local no_prompt="${3:-}"
  local name
  name="$(basename "$tgt")"

  if [[ -L "$tgt" ]]; then
    local existing_link
    existing_link="$(readlink "$tgt")"
    if [[ "$existing_link" == "$src" ]]; then
      info "$name symlink is already up to date"
      return 0
    fi
    if [[ ! -e "$existing_link" ]]; then
      # The old target is gone -- nothing is lost by repointing. Most likely
      # this repo (or its old checkout location) was moved, not a real
      # collision with someone else's symlink.
      rm "$tgt"
      ln -s "$src" "$tgt"
      info "$name symlink pointed at a missing path — repointed to this repo"
      return 0
    fi
    warn "$name is a symlink pointing elsewhere ($existing_link)"
    if [[ "$no_prompt" != "--no-collision-prompt" ]] && ask "Replace it with a symlink to this repo?"; then
      rm "$tgt"
      ln -s "$src" "$tgt"
      info "Replaced $name symlink"
    else
      warn "Skipped $name — leaving existing symlink in place"
    fi
    return 0
  fi

  if [[ -f "$tgt" ]]; then
    local src_tag
    src_tag="$(file_tag "$src")"
    if diff -q "$tgt" "$src" > /dev/null 2>&1; then
      # Identical content — just replace with a symlink so it stays in sync
      rm "$tgt"
      ln -s "$src" "$tgt"
      info "$name — replaced identical copy with symlink"
    elif [[ -n "$src_tag" && "$(file_tag "$tgt")" == "$src_tag" ]]; then
      # Tagged as this same tool, just an older/pre-symlink version of it --
      # not a collision with someone else's file. No need for the rename
      # dance below.
      rm "$tgt"
      ln -s "$src" "$tgt"
      info "$name — replaced older installed version with symlink"
    else
      warn "$name already exists and differs from this repo's version"
      if [[ "$no_prompt" != "--no-collision-prompt" ]]; then
        echo -e "     The dispatcher calls all ${BOLD}${name}.*${NC} files in the same directory."
        echo "     Renaming your file to ${name}.existing keeps it running alongside this repo's version."
        if ask "Rename your existing $name to ${name}.existing and install this repo's version?"; then
          mv "$tgt" "${tgt}.existing"
          ln -s "$src" "$tgt"
          info "Renamed existing hook to ${name}.existing, installed $name"
        else
          warn "Skipped $name — your existing file is unchanged"
        fi
      else
        warn "Skipped $name — your existing file is unchanged"
      fi
    fi
    return 0
  fi

  ln -s "$src" "$tgt"
  info "Installed $name symlink"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: add a git config include.path entry (idempotent)
# ─────────────────────────────────────────────────────────────────────────────
add_include() {
  local include_path="$1"
  local label="$2"

  local already_included
  already_included="$(git config --global --get-all include.path 2>/dev/null | grep -Fx "$include_path" || true)"

  if [[ -n "$already_included" ]]; then
    info "$label already included"
  else
    git config --global --add include.path "$include_path"
    info "Added $label to ~/.gitconfig"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Create ~/.githooks
# ─────────────────────────────────────────────────────────────────────────────
step "1. ~/.githooks directory"
echo "     Required by the hooks steps below."
if [[ -d "$HOOKS_DIR" ]]; then
  info "~/.githooks already exists"
elif ask "Create ~/.githooks?"; then
  mkdir -p "$HOOKS_DIR"
  info "Created ~/.githooks"
else
  skip
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. commit-msg dispatcher
# ─────────────────────────────────────────────────────────────────────────────
step "2. commit-msg hook (dispatcher)"
echo "     Calls all commit-msg.* hooks found in ~/.githooks."
if ask "Install commit-msg dispatcher?"; then
  install_symlink "$REPO_DIR/commit-msg" "$HOOKS_DIR/commit-msg"
  make_executable "$REPO_DIR/commit-msg"
else
  skip
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. commit-msg.branch-name
# ─────────────────────────────────────────────────────────────────────────────
step "3. commit-msg.branch-name hook"
echo "     Prepends the current branch name to every commit message."
if ask "Install commit-msg.branch-name?"; then
  install_symlink "$REPO_DIR/commit-msg.branch-name" "$HOOKS_DIR/commit-msg.branch-name" --no-collision-prompt
  make_executable "$REPO_DIR/commit-msg.branch-name"
else
  skip
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. Set core.hooksPath globally
# ─────────────────────────────────────────────────────────────────────────────
step "4. git core.hooksPath"
echo "     Points git to ~/.githooks so the hooks above are picked up globally."
if ask "Set core.hooksPath to ~/.githooks?"; then
  CURRENT_HOOKS_PATH="$(git config --global core.hooksPath 2>/dev/null || true)"
  if [[ "$CURRENT_HOOKS_PATH" == "$HOOKS_DIR" ]]; then
    info "core.hooksPath already set to ~/.githooks"
  elif [[ -n "$CURRENT_HOOKS_PATH" ]]; then
    warn "core.hooksPath is currently set to: $CURRENT_HOOKS_PATH"
    if ask "Update it to ~/.githooks?"; then
      git config --global core.hooksPath "$HOOKS_DIR"
      info "Updated core.hooksPath to ~/.githooks"
    else
      warn "Skipped — hooks may not run until core.hooksPath points to ~/.githooks"
    fi
  else
    git config --global core.hooksPath "$HOOKS_DIR"
    info "Set core.hooksPath to ~/.githooks"
  fi
else
  skip
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Branch tracking config
# ─────────────────────────────────────────────────────────────────────────────
step "5. Branch tracking config"
echo "     Sets [branch] autosetupmerge and autosetuprebase for stacked-PR workflows."
if ask "Install branch tracking config?"; then
  install_symlink "$REPO_DIR/.gitconfig.git-stuff-tracking" "$HOME/.gitconfig.git-stuff-tracking" --no-collision-prompt
  add_include "$HOME/.gitconfig.git-stuff-tracking" ".gitconfig.git-stuff-tracking"
else
  skip
fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. Aliases
# ─────────────────────────────────────────────────────────────────────────────
step "6. Aliases"
echo "     Adds: branch-name, pup, pown, pupl, notyours, testny, test-git-stuff."
if ask "Install aliases?"; then
  install_symlink "$REPO_DIR/.gitconfig.git-stuff-aliases" "$HOME/.gitconfig.git-stuff-aliases" --no-collision-prompt
  add_include "$HOME/.gitconfig.git-stuff-aliases" ".gitconfig.git-stuff-aliases"
else
  skip
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Done.${NC} Run ${BOLD}git test-git-stuff${NC} to verify the aliases loaded correctly."
echo ""

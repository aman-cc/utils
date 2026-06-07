#!/usr/bin/env bash
# Idempotent, best-effort setup for a fresh Debian/Ubuntu machine.
# Re-run safely; existing config files are diff-checked and backed up before replacement.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_BEGIN="# >>> utils setup >>>"
MARKER_END="# <<< utils setup <<<"

SUCCEEDED=()
FAILED=()
SKIPPED=()

log()  { printf '%b\n' "${YELLOW}>>${NC} $*"; }
ok()   { SUCCEEDED+=("$1"); printf '%b\n' "${GREEN}✓${NC} $1"; }
fail() { FAILED+=("$1"); printf '%b\n' "${RED}✗${NC} $1"; }
skip() { SKIPPED+=("$1"); printf '%b\n' "${YELLOW}↷${NC} $1 (skipped)"; }

run_step() {
	local label="$1"; shift
	if "$@"; then
		ok "$label"
	else
		fail "$label"
	fi
}

# ---- pre-flight -------------------------------------------------------------

if ! command -v apt-get >/dev/null 2>&1; then
	printf '%b\n' "${RED}This script targets Debian/Ubuntu (apt-get not found). Aborting.${NC}" >&2
	exit 1
fi

SUDO=""
if [[ $EUID -ne 0 ]]; then
	if ! command -v sudo >/dev/null 2>&1; then
		printf '%b\n' "${RED}sudo not found and not running as root. Aborting.${NC}" >&2
		exit 1
	fi
	if ! sudo -v; then
		printf '%b\n' "${RED}sudo authentication failed. Aborting.${NC}" >&2
		exit 1
	fi
	SUDO="sudo"
fi

# ---- helpers ----------------------------------------------------------------

apt_install_missing() {
	local pkgs=("$@") missing=()
	for p in "${pkgs[@]}"; do
		if dpkg -s "$p" >/dev/null 2>&1; then
			SKIPPED+=("apt: $p already installed")
		else
			missing+=("$p")
		fi
	done
	if [[ ${#missing[@]} -eq 0 ]]; then
		log "all apt packages already installed"
		return 0
	fi
	log "installing: ${missing[*]}"
	$SUDO apt-get install -y "${missing[@]}"
}

# append_block <target_file> <payload_file> [extra_lines_file]
# Appends payload (and optional extra lines) to target file between sentinel
# markers, but only if the markers aren't already present.
append_block() {
	local target="$1" payload="$2" extras="${3:-}"
	touch "$target"
	if grep -qF "$MARKER_BEGIN" "$target"; then
		return 1  # already present -> skip
	fi
	{
		printf '\n%s\n' "$MARKER_BEGIN"
		cat "$payload"
		if [[ -n "$extras" && -f "$extras" ]]; then
			printf '\n'
			cat "$extras"
		fi
		printf '%s\n' "$MARKER_END"
	} >> "$target"
}

# install_file <src> <dst>: copy only if different; backup existing dst first.
install_file() {
	local src="$1" dst="$2"
	mkdir -p "$(dirname "$dst")"
	if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
		return 1  # identical -> skip
	fi
	if [[ -e "$dst" ]]; then
		local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
		cp -p "$dst" "${dst}.bak.${stamp}"
	fi
	cp "$src" "$dst"
}

# ---- 1. apt --------------------------------------------------------------

run_step "apt update" $SUDO apt-get update

PKGS=(
	git curl wget tmux vim neovim
	python3 python3-dev python3-venv
	fzf ripgrep fd-find bat
)
run_step "apt install" apt_install_missing "${PKGS[@]}"

# ---- 2. ~/.bashrc -------------------------------------------------------

# Build a small extras file (PATH + Debian-renamed binary aliases) appended
# into the same marker block, so re-runs stay idempotent.
EXTRAS_FILE="$(mktemp)"
trap 'rm -f "$EXTRAS_FILE"' EXIT
{
	echo 'export PATH="$HOME/.local/bin:$PATH"'
	command -v fdfind  >/dev/null 2>&1 && echo 'alias fd=fdfind'
	command -v batcat  >/dev/null 2>&1 && echo 'alias bat=batcat'
} > "$EXTRAS_FILE"

if append_block "$HOME/.bashrc" "$SCRIPT_DIR/.bashrc" "$EXTRAS_FILE"; then
	ok "appended bashrc block"
else
	skip "bashrc block already present"
fi

# ---- 3. ~/.inputrc (one-time bootstrap) ---------------------------------

if [[ ! -f "$HOME/.inputrc" ]]; then
	{
		echo '$include /etc/inputrc'
		echo 'set completion-ignore-case On'
	} > "$HOME/.inputrc"
	ok "created ~/.inputrc"
elif ! grep -q 'completion-ignore-case' "$HOME/.inputrc"; then
	echo 'set completion-ignore-case On' >> "$HOME/.inputrc"
	ok "added completion-ignore-case to ~/.inputrc"
else
	skip "~/.inputrc already configured"
fi

# ---- 4. ~/.tmux.conf ----------------------------------------------------

if install_file "$SCRIPT_DIR/.tmux.conf" "$HOME/.tmux.conf"; then
	ok "installed ~/.tmux.conf"
else
	skip "~/.tmux.conf already up-to-date"
fi

# ---- 5. neovim config + vim-plug ---------------------------------------

if install_file "$SCRIPT_DIR/neovim_init.vim" "$HOME/.config/nvim/init.vim"; then
	ok "installed ~/.config/nvim/init.vim"
else
	skip "~/.config/nvim/init.vim already up-to-date"
fi

PLUG_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/autoload/plug.vim"
if [[ -f "$PLUG_PATH" ]]; then
	skip "vim-plug already installed"
else
	run_step "install vim-plug" bash -c \
		"curl -fLo '$PLUG_PATH' --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
fi

# ---- 6. python venv -----------------------------------------------------

if [[ -x "$HOME/.venv/bin/python" ]]; then
	skip "~/.venv already exists"
else
	run_step "create ~/.venv" python3 -m venv "$HOME/.venv"
fi

if [[ -x "$HOME/.venv/bin/python" ]]; then
	run_step "pip install python deps" \
		"$HOME/.venv/bin/python" -m pip install -U \
		pip pynvim ruff numpy opencv-python pillow typing_extensions
fi

# ---- 7. neovim PlugInstall ---------------------------------------------

if command -v nvim >/dev/null 2>&1 && [[ -f "$PLUG_PATH" ]]; then
	run_step "nvim PlugInstall" nvim --headless +PlugInstall +qall
else
	skip "PlugInstall (nvim or plug.vim missing)"
fi

# ---- summary ------------------------------------------------------------

printf '\n%b\n' "${YELLOW}==== Setup summary ====${NC}"
printf '%b\n' "${GREEN}✓ ${#SUCCEEDED[@]} succeeded${NC}"
printf '%b\n' "${YELLOW}↷ ${#SKIPPED[@]} skipped${NC}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
	printf '%b\n' "${RED}✗ ${#FAILED[@]} failed:${NC}"
	for f in "${FAILED[@]}"; do
		printf '    - %s\n' "$f"
	done
else
	printf '%b\n' "${GREEN}✗ 0 failed${NC}"
fi

printf '\n%bsource ~/.bashrc%b to pick up new shell config.\n' "$GREEN" "$NC"

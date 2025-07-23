#!/usr/bin/env bash
#
# setup.sh - cross-platform setup for Resume Matcher
#
# Usage:
#   ./setup.sh [--help] [--start-dev]
#
# Requirements:
#   3 Bash 4.4+ (for associative arrays)
#   3 curl (for uv & ollama installers, if needed)
#
# After setup:
#   npm run dev       # start development server
#   npm run build     # build for production

set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
IFS=$'\n\t'

#	6 Detect OS for compatibility 	6#
OS="$(uname -s)"
case "$OS" in
  Linux*)   OS_TYPE="Linux" ;;
  Darwin*)  OS_TYPE="macOS" ;;
  *)        OS_TYPE="$OS" ;;
esac

#	6 CLI help 	6#
usage() {
  cat <<EOF
Usage: $0 [--help] [--start-dev]

Options:
  --help       Show this help message and exit
  --start-dev  After setup completes, start the dev server (with graceful SIGINT handling)

This script will:
  3 Verify required tools: node, npm, python3, pip3, uv
  3 Install Ollama & pull gemma3:4b model
  3 Install root dependencies via npm ci
  3 Bootstrap both root and backend .env files
  3 Bootstrap backend venv and install Python deps via uv
  3 Install frontend dependencies via npm ci
EOF
}

START_DEV=false
if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ "${1:-}" == "--start-dev" ]]; then
  START_DEV=true
fi

#	6 Logging helpers 	6#
info()    { echo -e "  $*"; }
success() { echo -e " $*"; }
error()   { echo -e " $*" >&2; exit 1; }

info "Detected operating system: $OS_TYPE"

#	6 1. Prerequisite checks 	6#
check_cmd() {
  local cmd=$1
  if ! command -v "$cmd" &> /dev/null; then
    error "$cmd is not installed. Please install it and retry."
  fi
}

check_node_version() {
  local min_major=18
  local ver
  ver=$(node --version | sed 's/^v\([0-9]*\).*/\1/')
  if (( ver < min_major )); then
    error "Node.js v${min_major}+ is required (found v$(node --version))."
  fi
}

info "Checking prerequisites"
check_cmd node
check_node_version
check_cmd npm
check_cmd python3

if ! command -v pip3 &> /dev/null; then
  if [[ "$OS_TYPE" == "Linux" && -x "$(command -v apt-get)" ]]; then
    info "pip3 not found; installing via apt-get"
    sudo apt-get update && sudo apt-get install -y python3-pip || error "Failed to install python3-pip"
  elif [[ "$OS_TYPE" == "Linux" && -x "$(command -v yum)" ]]; then
    info "pip3 not found; installing via yum"
    sudo yum install -y python3-pip || error "Failed to install python3-pip"
  else
    info "pip3 not found; bootstrapping via ensurepip"
    python3 -m ensurepip --upgrade || error "ensurepip failed"
  fi
fi
check_cmd pip3
success "pip3 is available"

# ensure uv
if ! command -v uv &> /dev/null; then
  info "uv not found; installing via Astral.sh"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
check_cmd uv
success "All prerequisites satisfied."

#	6 2. Ollama & model setup 	6#
info "Checking Ollama installation"
if ! command -v ollama &> /dev/null; then
  info "ollama not found; installing"
  if [[ "$OS_TYPE" == "macOS" ]]; then
    brew install ollama || error "Failed to install Ollama via Homebrew"
  else
    # Download the install script to a temp file
    TMP_INSTALL_SCRIPT=$(mktemp)
    curl -LsSf https://ollama.com/install.sh -o "$TMP_INSTALL_SCRIPT" || error "Failed to download Ollama install script"
    info "Ollama install script downloaded to $TMP_INSTALL_SCRIPT"
    info "Please verify the script before execution."
    # Prompt user to continue
    read -p "Do you want to execute the Ollama install script now? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      sh "$TMP_INSTALL_SCRIPT" || error "Failed to execute Ollama install script"
      success "Ollama installed"
    else
      error "Ollama installation aborted by user."
    fi
    rm -f "$TMP_INSTALL_SCRIPT"
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

if ! ollama list | grep -q 'gemma3:4b'; then
  info "Pulling gemma3:4b model"
  ollama pull gemma3:4b || error "Failed to pull gemma3:4b"
  success "gemma3:4b model ready"
else
  info "gemma3:4b model already present	6skipping"
fi

#	6 3. Bootstrap root .env 	6#
if [[ -f .env.example && ! -f .env ]]; then
  info "Bootstrapping root .env from .env.example"
  cp .env.example .env
  success "Root .env created"
elif [[ -f .env ]]; then
  info "Root .env already exists	6skipping"
else
  info "No .env.example at root	6skipping"
fi

#	6 4. Install root dependencies 	6#
info "Installing root dependencies with npm ci"
npm ci
success "Root dependencies installed."

#	6 5. Setup backend 	6#
info "Setting up backend (apps/backend)"
(
  cd apps/backend

  # bootstrap backend .env
  if [[ -f .env.sample && ! -f .env ]]; then
    info "Bootstrapping backend .env from .env.sample"
    cp .env.sample .env
    success "Backend .env created"
  else
    info "Backend .env exists or .env.sample missing	6skipping"
  fi

  info "Syncing Python deps via uv"
  uv sync
  success "Backend dependencies ready."
)

#	6 6. Setup frontend 	6#
info "Setting up frontend (apps/frontend)"
(
  cd apps/frontend
  # bootstrap frontend .env
  if [[ -f .env.sample && ! -f .env ]]; then
    info "Bootstrapping frontend .env from .env.sample"
    cp .env.sample .env
    success "frontend .env created"
  else
    info "frontend .env exists or .env.sample missing	6skipping"
  fi

  info "Installing frontend deps with npm ci"
  npm ci
  success "Frontend dependencies ready."
)

#	6 7. Finish or start dev 	6#
if [[ "$START_DEV" == true ]]; then
  info "Starting development server"
  # trap SIGINT for graceful shutdown
  trap 'info "Gracefully shutting down development server."; exit 0' SIGINT
  npm run dev
else
  success " Setup complete!

Next steps:
  3 Run \`npm run dev\` to start in development mode.
  3 Run \`npm run build\` for production.
  3 See SETUP.md for more details."
fi

#!/usr/bin/env bash
#
# install_comfyui.sh - Install ComfyUI + ComfyUI-Manager on Linux inside a
# Python virtual environment, in a directory of your choice.
#
# Usage:
#   ./install_comfyui.sh                 # interactive (asks for folder + GPU type)
#   ./install_comfyui.sh /path/to/dir    # install into /path/to/dir/ComfyUI
#   ./install_comfyui.sh -d DIR -g cpu -y
#
# Options:
#   -d, --dir DIR       Parent folder to install into (ComfyUI/ is created inside)
#   -g, --gpu TYPE      nvidia | amd | intel | cpu   (default: auto-detect)
#   -p, --python BIN    Python interpreter to use (default: python3)
#   -y, --yes           Non-interactive; accept defaults, don't prompt
#   -h, --help          Show this help
#
# Env overrides:
#   TORCH_INDEX_URL     Custom PyTorch wheel index (skips the GPU-based default)
#
set -euo pipefail

COMFYUI_REPO="https://github.com/comfyanonymous/ComfyUI.git"
MANAGER_REPO="https://github.com/Comfy-Org/ComfyUI-Manager.git"

# PyTorch wheel indexes per backend. Override with TORCH_INDEX_URL if needed.
TORCH_INDEX_NVIDIA="https://download.pytorch.org/whl/cu128"
TORCH_INDEX_AMD="https://download.pytorch.org/whl/rocm6.4"
TORCH_INDEX_CPU="https://download.pytorch.org/whl/cpu"

INSTALL_PARENT=""
GPU_TYPE=""
PYTHON_BIN="python3"
ASSUME_YES=0

# ---------------------------------------------------------------- helpers ---
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi

info()  { echo "${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
ok()    { echo "${C_GREEN} ✔${C_RESET} $*"; }
warn()  { echo "${C_YELLOW} !${C_RESET} $*" >&2; }
die()   { echo "${C_RED}ERROR:${C_RESET} $*" >&2; exit 1; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0; }

ask() {
  # ask VAR "prompt" "default"
  local -n _out=$1
  local prompt=$2 default=${3:-}
  if (( ASSUME_YES )); then
    _out=$default
    return
  fi
  if [[ -n $default ]]; then
    read -r -p "$prompt [$default]: " _out
    _out=${_out:-$default}
  else
    read -r -p "$prompt: " _out
  fi
}

confirm() {
  (( ASSUME_YES )) && return 0
  local reply
  read -r -p "$1 [Y/n]: " reply
  [[ -z $reply || $reply =~ ^[Yy]$ ]]
}

# ------------------------------------------------------------ parse args ---
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--dir)    INSTALL_PARENT=$2; shift 2 ;;
    -g|--gpu)    GPU_TYPE=$2; shift 2 ;;
    -p|--python) PYTHON_BIN=$2; shift 2 ;;
    -y|--yes)    ASSUME_YES=1; shift ;;
    -h|--help)   usage ;;
    -*)          die "Unknown option: $1 (see --help)" ;;
    *)           INSTALL_PARENT=$1; shift ;;
  esac
done

# ------------------------------------------------------- prerequisites ---
info "Checking prerequisites"

[[ $(uname -s) == Linux ]] || die "This script is for Linux only."

command -v git >/dev/null 2>&1 || die "git is not installed. Install it (e.g. 'sudo apt install git') and re-run."
ok "git: $(git --version)"

command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "Python interpreter '$PYTHON_BIN' not found. Install python3 or pass -p /path/to/python."

PY_VERSION=$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
"$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' \
  || die "Python >= 3.9 is required, found $PY_VERSION."
ok "python: $PYTHON_BIN ($PY_VERSION)"

"$PYTHON_BIN" -c 'import venv, ensurepip' >/dev/null 2>&1 \
  || die "The 'venv' module is missing. On Debian/Ubuntu run: sudo apt install python${PY_VERSION}-venv"
ok "venv module available"

# ------------------------------------------------------ install folder ---
echo
if [[ -z $INSTALL_PARENT ]]; then
  ask INSTALL_PARENT "Where should ComfyUI be installed? (a 'ComfyUI' folder will be created inside)" "$HOME"
fi
# Expand ~ and make absolute
INSTALL_PARENT=${INSTALL_PARENT/#\~/$HOME}
INSTALL_PARENT=$(realpath -m "$INSTALL_PARENT")
COMFY_DIR="$INSTALL_PARENT/ComfyUI"
VENV_DIR="$COMFY_DIR/venv"
MANAGER_DIR="$COMFY_DIR/custom_nodes/ComfyUI-Manager"

# -------------------------------------------------------- GPU detection ---
detect_gpu() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    echo nvidia
  elif command -v rocminfo >/dev/null 2>&1 || [[ -d /opt/rocm ]]; then
    echo amd
  elif [[ -e /dev/dri/renderD128 ]] && lspci 2>/dev/null | grep -qi 'VGA.*Intel\|Display.*Intel'; then
    echo intel
  else
    echo cpu
  fi
}

if [[ -z $GPU_TYPE ]]; then
  DETECTED=$(detect_gpu)
  ask GPU_TYPE "GPU backend to install PyTorch for (nvidia/amd/intel/cpu)" "$DETECTED"
fi
GPU_TYPE=${GPU_TYPE,,}

case $GPU_TYPE in
  nvidia) TORCH_INDEX=$TORCH_INDEX_NVIDIA ;;
  amd)    TORCH_INDEX=$TORCH_INDEX_AMD ;;
  cpu)    TORCH_INDEX=$TORCH_INDEX_CPU ;;
  intel)  TORCH_INDEX="" ;;  # XPU wheels come from the default PyPI index
  *)      die "Unknown GPU type '$GPU_TYPE'. Use nvidia, amd, intel or cpu." ;;
esac
[[ -n ${TORCH_INDEX_URL:-} ]] && TORCH_INDEX=$TORCH_INDEX_URL

# ---------------------------------------------------------------- summary ---
echo
echo "${C_BOLD}Install plan${C_RESET}"
echo "  ComfyUI dir : $COMFY_DIR"
echo "  Virtualenv  : $VENV_DIR"
echo "  Manager dir : $MANAGER_DIR"
echo "  Python      : $PYTHON_BIN ($PY_VERSION)"
echo "  GPU backend : $GPU_TYPE"
echo "  Torch index : ${TORCH_INDEX:-<default PyPI>}"
echo
confirm "Proceed?" || { echo "Aborted."; exit 0; }

mkdir -p "$INSTALL_PARENT" || die "Cannot create directory: $INSTALL_PARENT"

# ---------------------------------------------------------- clone ComfyUI ---
echo
if [[ -d $COMFY_DIR/.git ]]; then
  info "ComfyUI already present, pulling latest changes"
  git -C "$COMFY_DIR" pull --ff-only || warn "git pull failed; continuing with the existing checkout."
elif [[ -e $COMFY_DIR ]]; then
  die "$COMFY_DIR exists but is not a git checkout. Remove it or pick another folder."
else
  info "Cloning ComfyUI"
  git clone "$COMFYUI_REPO" "$COMFY_DIR"
fi
ok "ComfyUI source ready"

# --------------------------------------------------------- virtualenv ---
if [[ ! -x $VENV_DIR/bin/python ]]; then
  info "Creating virtual environment"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
else
  info "Reusing existing virtual environment"
fi
VENV_PY="$VENV_DIR/bin/python"
ok "venv: $VENV_DIR"

info "Upgrading pip / setuptools / wheel"
"$VENV_PY" -m pip install --upgrade pip setuptools wheel

# ------------------------------------------------------------- PyTorch ---
info "Installing PyTorch ($GPU_TYPE)"
if [[ -n $TORCH_INDEX ]]; then
  "$VENV_PY" -m pip install torch torchvision torchaudio --index-url "$TORCH_INDEX"
else
  "$VENV_PY" -m pip install torch torchvision torchaudio
fi
ok "PyTorch installed"

# ---------------------------------------------------- ComfyUI requirements ---
info "Installing ComfyUI requirements"
"$VENV_PY" -m pip install -r "$COMFY_DIR/requirements.txt"
ok "ComfyUI requirements installed"

# ---------------------------------------------------- ComfyUI-Manager ---
mkdir -p "$COMFY_DIR/custom_nodes"
if [[ -d $MANAGER_DIR/.git ]]; then
  info "ComfyUI-Manager already present, pulling latest changes"
  git -C "$MANAGER_DIR" pull --ff-only || warn "git pull failed; continuing with the existing checkout."
else
  info "Cloning ComfyUI-Manager"
  git clone "$MANAGER_REPO" "$MANAGER_DIR"
fi
if [[ -f $MANAGER_DIR/requirements.txt ]]; then
  info "Installing ComfyUI-Manager requirements"
  "$VENV_PY" -m pip install -r "$MANAGER_DIR/requirements.txt"
fi
ok "ComfyUI-Manager installed"

# --------------------------------------------------------- launcher ---
LAUNCHER="$COMFY_DIR/run_comfyui.sh"
info "Writing launcher script"
cat > "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
# Launch ComfyUI using its virtual environment. Extra args are passed to main.py,
# e.g.:  ./run_comfyui.sh --listen 0.0.0.0 --port 8188
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
# shellcheck disable=SC1091
source venv/bin/activate
exec python main.py "$@"
EOF
chmod +x "$LAUNCHER"
ok "launcher: $LAUNCHER"

# --------------------------------------------------------- done ---
echo
echo "${C_GREEN}${C_BOLD}ComfyUI + ComfyUI-Manager installed successfully.${C_RESET}"
echo
echo "To start ComfyUI:"
echo "  $LAUNCHER"
echo
echo "Then open http://127.0.0.1:8188 in your browser."
echo "Place models in: $COMFY_DIR/models/checkpoints"
case $GPU_TYPE in
  cpu) echo; echo "Note: CPU mode selected. Run with:  $LAUNCHER --cpu" ;;
  amd) echo; echo "Note: on unsupported AMD GPUs you may need:  HSA_OVERRIDE_GFX_VERSION=10.3.0 $LAUNCHER" ;;
esac

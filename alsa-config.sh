#!/usr/bin/env bash
# ==============================================================================
# ALSA UCM Configurator for Lenovo Yoga Slim 7X (Qualcomm X1E80100)
# Repository: https://github.com/master2619/lenovo-yoga-slim7x-audio-linux
# ==============================================================================

# Strict bash execution parameters
set -euo pipefail

# --- Visual Output Parameters ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

# --- Configuration & Paths ---
REPO_URL="https://github.com/master2619/lenovo-yoga-slim7x-audio-linux.git"
UCM_BASE_DIR="/usr/share/alsa/ucm2"
QCOM_DIR="${UCM_BASE_DIR}/Qualcomm/x1e80100"
CARD_CONF_DIR="${UCM_BASE_DIR}/conf.d/X1E80100LENOVOY"
TMP_DIR=$(mktemp -d -t alsa-yoga-XXXXXX)
ROLLBACK_LOG="/tmp/alsa_yoga_rollback_$(date +%s).log"

# --- Helper Functions ---
echo_step() { echo -e "${C_CYAN}${C_BOLD}[*]${C_RESET} $1"; }
echo_success() { echo -e "${C_GREEN}${C_BOLD}[+]${C_RESET} $1"; }
echo_warn() { echo -e "${C_YELLOW}${C_BOLD}[!]${C_RESET} $1"; }
echo_error() { echo -e "${C_RED}${C_BOLD}[x]${C_RESET} $1"; }

cleanup() {
    if [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

# --- Rollback Mechanism ---
rollback() {
    echo ""
    echo_warn "Initiating rollback sequence..."
    if [ ! -f "$ROLLBACK_LOG" ]; then
        echo_step "No rollback log found. Nothing to revert."
        return 0
    fi

    while IFS= read -r line; do
        ACTION=$(echo "$line" | cut -d':' -f1)
        FILE_PATH=$(echo "$line" | cut -d':' -f2-)

        if [ "$ACTION" == "NEW" ]; then
            if [ -f "$FILE_PATH" ]; then
                rm -f "$FILE_PATH"
                echo_step "Removed newly created file: $FILE_PATH"
            fi
        elif [ "$ACTION" == "OVERWRITTEN" ]; then
            if [ -f "${FILE_PATH}.bak" ]; then
                mv "${FILE_PATH}.bak" "$FILE_PATH"
                echo_step "Restored backup: $FILE_PATH"
            fi
        fi
    done < "$ROLLBACK_LOG"
    
    echo_success "Rollback complete."
}

# Trap errors to offer rollback
error_handler() {
    echo ""
    echo_error "An error occurred during execution!"
    read -p "$(echo -e ${C_YELLOW}"Do you want to roll back changes? (y/N): "${C_RESET})" choice
    case "$choice" in 
        y|Y ) rollback ;;
        * ) echo_step "Keeping current state. Temporary files cleaned up." ;;
    esac
    exit 1
}
trap error_handler ERR

# --- File Deployment Logic ---
safe_install() {
    local src="$1"
    local dest_dir="$2"
    local dest_file="$dest_dir/$(basename "$src")"

    mkdir -p "$dest_dir"

    if [ -f "$dest_file" ]; then
        cp -a "$dest_file" "${dest_file}.bak"
        echo "OVERWRITTEN:$dest_file" >> "$ROLLBACK_LOG"
        echo_step "Created backup: ${dest_file}.bak"
    else
        echo "NEW:$dest_file" >> "$ROLLBACK_LOG"
    fi

    cp "$src" "$dest_file"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

clear
echo -e "${C_BLUE}${C_BOLD}"
echo "============================================================"
echo "    Lenovo Yoga Slim 7X (X1E80100) Audio Enablement         "
echo "============================================================"
echo -e "${C_RESET}"

# 1. Pre-flight checks
if [ "$EUID" -ne 0 ]; then
    echo_error "This script must be run as root to modify ALSA directories."
    echo_step "Please re-run with: sudo $0"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo_error "'git' is required but not installed. Please install it first."
    exit 1
fi

touch "$ROLLBACK_LOG"
echo_step "Rollback log initialized at $ROLLBACK_LOG"

# 2. User Confirmation
echo ""
echo_warn "This script will download experimental DSP configurations and install"
echo_warn "them into your system's ALSA UCM directories (/usr/share/alsa/ucm2)."
echo ""
read -p "$(echo -e ${C_GREEN}${C_BOLD}"Are you sure you want to proceed? (y/N): "${C_RESET})" confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo_error "Aborted by user."
    exit 0
fi

echo ""

# 3. Clone Repository
echo_step "Fetching repository from GitHub..."
git clone --quiet "$REPO_URL" "$TMP_DIR/repo"
echo_success "Repository cloned successfully."

# 4. Extract and Place Files
echo_step "Deploying ALSA UCM files..."

cd "$TMP_DIR/repo"

# The main card configuration file needs to go to conf.d
if [ -f "X1E80100LENOVOY.conf" ]; then
    echo_step "Installing main card config (X1E80100LENOVOY.conf) to $CARD_CONF_DIR"
    safe_install "X1E80100LENOVOY.conf" "$CARD_CONF_DIR"
else
    echo_warn "X1E80100LENOVOY.conf not found in repo! Topology may fail to load."
fi

# The rest of the UCM configurations and DSP resources go to the Qualcomm base directory
echo_step "Installing component configurations and DSP data to $QCOM_DIR"

# Copy all configurations EXCEPT the main card one which we just moved
for conf_file in *.conf; do
    if [ "$conf_file" != "X1E80100LENOVOY.conf" ]; then
        safe_install "$conf_file" "$QCOM_DIR"
    fi
done

# Copy binary DSP filters and data
if [ -f "filter.irs" ]; then safe_install "filter.irs" "$QCOM_DIR"; fi
if [ -f "filter.wav" ]; then safe_install "filter.wav" "$QCOM_DIR"; fi
if [ -f "alsa_controls.txt" ]; then safe_install "alsa_controls.txt" "$QCOM_DIR"; fi

echo_success "Files deployed successfully!"

# 5. Finalize
echo ""
echo_success "Installation Complete."
echo_step "Modified files have been backed up as '.bak' in their respective directories."
echo_step "To apply changes, reload ALSA state or reboot your machine:"
echo -e "    ${C_YELLOW}sudo alsactl restore${C_RESET}  OR  ${C_YELLOW}sudo systemctl restart alsa-state${C_RESET}"
echo ""

# Post-install option to rollback immediately if user changed their mind
read -p "$(echo -e ${C_YELLOW}"Did this break your audio? Do you want to rollback right now? (y/N): "${C_RESET})" rb_choice
if [[ "$rb_choice" =~ ^[Yy]$ ]]; then
    rollback
else
    echo_step "Installation finalized. Exiting safely."
fi

exit 0

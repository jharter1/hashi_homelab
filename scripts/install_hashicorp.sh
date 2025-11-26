#!/usr/bin/env bash
#
# install_hashicorp.sh
# Downloads and installs HashiCorp binaries (Consul, Nomad, Vault)
# Designed for use with Packer image builds
#

set -euo pipefail  # Exit on error, undefined vars, and pipe failures
IFS=$'\n\t'        # Set safer field separator

#======================================
# Configuration
#======================================

# Version variables are accessed via indirect expansion (${!version_var})
# shellcheck disable=SC2034
readonly CONSUL_VERSION="1.18.0"
# shellcheck disable=SC2034
readonly NOMAD_VERSION="1.7.5"
# shellcheck disable=SC2034
readonly VAULT_VERSION="1.16.0"
readonly BINARIES=("consul" "nomad" "vault")

readonly TEMP_DIR="${HOME}/hashicorp-install"
readonly INSTALL_DIR="/usr/local/bin"
readonly DOWNLOAD_BASE_URL="https://releases.hashicorp.com"

#======================================
# Functions
#======================================

# Print error message and exit
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Print informational message
log_info() {
    echo "[INFO] $1"
}

# Download and install a single binary
install_binary() {
    local binary="$1"
    local version_var="${binary^^}_VERSION"
    local version="${!version_var}"
    
    log_info "Installing ${binary} version ${version}..."
    
    # Check available disk space in temp directory (need ~300MB for vault)
    local temp_space_mb
    temp_space_mb=$(df -BM "${TEMP_DIR}" | awk 'NR==2 {print $4}' | sed 's/M//')
    if [[ ${temp_space_mb} -lt 300 ]]; then
        error_exit "Insufficient disk space in ${TEMP_DIR}: ${temp_space_mb}MB available, need at least 300MB"
    fi
    
    local zip_file="${TEMP_DIR}/${binary}.zip"
    local download_url="${DOWNLOAD_BASE_URL}/${binary}/${version}/${binary}_${version}_linux_amd64.zip"
    
    # Verify destination is writable
    if ! touch "${zip_file}.test" 2>/dev/null; then
        error_exit "Cannot write to ${TEMP_DIR} - check permissions"
    fi
    rm -f "${zip_file}.test"
    
    # Download with retries and proper error handling
    # Increased timeout for large files and added retry parameters
    if ! curl --fail --silent --show-error --location \
              --retry 5 --retry-delay 10 --retry-max-time 300 \
              --connect-timeout 30 --max-time 600 \
              --output "${zip_file}" \
              "${download_url}"; then
        error_exit "Failed to download ${binary} from ${download_url}"
    fi
    
    # Unzip with error handling
    if ! unzip -q -o -d "${TEMP_DIR}" "${zip_file}"; then
        error_exit "Failed to unzip ${binary}"
    fi
    
    # Verify binary exists before moving
    if [[ ! -f "${TEMP_DIR}/${binary}" ]]; then
        error_exit "Binary file ${binary} not found after extraction"
    fi
    
    # Make executable and move to install directory
    chmod +x "${TEMP_DIR}/${binary}"
    if ! sudo mv "${TEMP_DIR}/${binary}" "${INSTALL_DIR}/${binary}"; then
        error_exit "Failed to move ${binary} to ${INSTALL_DIR}"
    fi
    
    # Verify installation
    if ! command -v "${binary}" >/dev/null 2>&1; then
        error_exit "${binary} installation failed - binary not found in PATH"
    fi
    
    local version_output
    version_output=$("${binary}" --version | head -n 1)
    log_info "${binary} installed successfully: ${version_output}"
}

# Clean up temporary files
cleanup() {
    if [[ -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "${TEMP_DIR}"
    fi
}

#======================================
# Main Script
#======================================

main() {
    log_info "Starting HashiCorp binary installation..."
    
    # Ensure required commands are available
    for cmd in curl unzip sudo; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            error_exit "Required command '${cmd}' not found"
        fi
    done
    
    # Create directories
    mkdir -p "${TEMP_DIR}"
    sudo mkdir -p "${INSTALL_DIR}"
    
    # Install each binary
    for binary in "${BINARIES[@]}"; do
        install_binary "${binary}"
    done
    
    # Cleanup temporary files
    cleanup
    
    log_info "All HashiCorp binaries installed successfully"
    
    # Optimize disk image size for Packer
    log_info "Running fstrim to optimize image size..."
    sudo fstrim -av || log_info "fstrim not available or failed (non-critical)"
    
    log_info "Installation complete"
}

# Run main function
main "$@"
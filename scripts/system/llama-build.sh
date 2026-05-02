#!/bin/bash
# Install required build dependencies
# =============================================================================
install_dependencies() {
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_log "Would install build dependencies"
        return 0
    fi
    
    log "Installing build dependencies..."
    
    local os_name=""
    local os_version=""
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_name="linux"
        os_version=$(grep -oP 'VERSION_ID=\\n=======
# =============================================================================
# Install required build dependencies
# =============================================================================
install_dependencies() {
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_log "Would install build dependencies"
        return 0
    fi
    
    log "Installing build dependencies..."
    
    local os_name=""
    local os_version=""
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_name="linux"
        os_version=$(grep -oP 'VERSION_ID=\K[^\\"]+' /etc/os-release 2>/dev/null || echo "unknown")
        
        log "Detected Linux distribution: $os_version"
        
        if [[ "$os_version" == *"ubuntu"* || "$os_version" == *"debian"* || "$os_version" == *"pop"* ]]; then
            log "Installing dependencies for Debian/Ubuntu-based system..."
            dry_run_wrapper "sudo apt-get update && sudo apt-get install -y git make cmake gcc g++ python3 python3-pip wget curl jq" \
                "Install build essentials"
        elif [[ "$os_version" == *"fedora"* || "$os_version" == *"rhel"* || "$os_version" == *"centos"* ]]; then
            log "Installing dependencies for Fedora/RHEL-based system..."
            dry_run_wrapper "sudo dnf install -y git make cmake gcc gcc-c++ python3 python3-pip wget curl jq" \
                "Install build essentials"
        elif [[ "$os_version" == *"arch"* ]]; then
            log "Installing dependencies for Arch-based system..."
            dry_run_wrapper "sudo pacman -Syu --noconfirm git make cmake gcc python python-pip wget curl jq" \
                "Install build essentials"
        else
            log "Unknown Linux distribution, attempting generic install..."
            dry_run_wrapper "sudo apt-get update && sudo apt-get install -y git make cmake gcc g++ python3 python3-pip wget curl jq 2>/dev/null || \
                           sudo dnf install -y git make cmake gcc gcc-c++ python3 python3-pip wget curl jq 2>/dev/null || \
                           sudo pacman -Syu --noconfirm git make cmake gcc python python-pip wget curl jq 2>/dev/null" \
                "Install build essentials (generic)"
        fi
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_name="macos"
        os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
        
        log "Detected macOS: $os_version"
        
        if ! command -v brew &>/dev/null; then
            warn "Homebrew not found, installing Homebrew first..."
            dry_run_wrapper "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" \
                "Install Homebrew"
        fi
        
        dry_run_wrapper "brew install git make cmake pkg-config jq wget curl" \
            "Install build essentials via Homebrew"
        
    else
        error "Unsupported OS: $OSTYPE"
        return 1
    fi
    
    success "Build dependencies installed"
}

# =============================================================================
# Parse Command Line Options
# =============================================================================
parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backend)
                FORCE_BACKEND="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --branch)
                DEFAULT_BRANCH="$2"
                shift 2
                ;;
            --threads)
                BUILD_THREADS="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
}

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
${CYAN}Hemlock Llama.cpp Builder${NC}

Builds Llama.cpp with optimal configuration based on system hardware.
Supports: CPU, CUDA, ROCm, Metal, Vulkan backends

${BLUE}Usage:${NC}
  $0 [OPTIONS] <COMMAND>

${BLUE}Options:${NC}
  --backend <type>    Specify backend: auto, metal, cuda, rocm, vulkan, cpu (default: auto)
  --dry-run           Preview actions without executing
  --verbose, -v       Enable verbose output
  --help, -h          Show this help
  --clean             Clean build files before building
  --branch <name>     Use specific llama.cpp branch (default: master)
  --threads <n>       Number of build threads (default: auto)

${BLUE}Commands:${NC}
  build              Build Llama.cpp (default)
  auto               Auto-detect and build (same as build)
  build-cpu          Force CPU-only build
  build-cuda         Force CUDA build
  build-metal        Force Metal build
  build-rocm         Force ROCm build
  build-vulkan       Force Vulkan build
  scan               Run hardware scan only
  verify             Verify installation
  clean              Clean build files
  install-deps       Install required dependencies

${BLUE}Examples:${NC}
  $0                                     # Auto-detect and build
  $0 --backend auto --verbose           # Auto with verbose
  $0 --backend cuda                      # Force CUDA build
  $0 --backend metal --dry-run          # Preview Metal build
  $0 build-cpu                           # Force CPU build
  $0 install-deps                        # Install dependencies only
  $0 clean                               # Clean build files

EOF
}

# =============================================================================
# Main
# =============================================================================
main() {
    local command="${1:-}"
    shift
    
    # Parse options
    parse_options "$@"
    
    # Set first positional argument back after options are consumed
    # This allows commands like: ./llama-build.sh --backend cuda build
    
    # Show help if no command given
    if [[ "$command" == "" && $# -eq 0 ]]; then
        if [[ "$FORCE_BACKEND" != "" || "$DRY_RUN" == true || "$VERBOSE" == true ]]; then
            # If flags provided, assume build command
            command="build"
        else
            usage
            exit 0
        fi
    fi
    
    # Handle commands
    case "$command" in
        build|auto|"")
            if [[ "$CLEAN_BUILD" == true ]]; then
                clean_build
            fi
            auto_build
            ;;
        build-cpu)
            if [[ "$CLEAN_BUILD" == true ]]; then
                clean_build
            fi
            build_cpu
            ;;
        build-cuda)
            if [[ "$CLEAN_BUILD" == true ]]; then
                clean_build
            fi
            build_cuda
            ;;
        build-metal)
            if [[ "$CLEAN_BUILD" == true ]]; then
                clean_build
            fi
            build_metal
            ;;
        build-rocm)
            if [[ "$CLEAN_BUILD" == true ]]; then
                clean_build
            fi
            build_rocm
            ;;
        build-vulkan)
            if [[ "$CLEAN_BUILD" == true ]]; then
                clean_build
            fi
            build_vulkan
            ;;
        scan)
            if [[ -f "$HARDWARE_SCAN_SCRIPT" ]]; then
                bash "$HARDWARE_SCAN_SCRIPT"
            else
                error "Hardware scanner not found"
                exit 1
            fi
            ;;
        verify)
            verify_installation
            ;;
        clean)
            clean_build
            ;;
        install-deps)
            install_dependencies
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"=============================================================================
# Hemlock Llama.cpp Builder
# 
# Builds Llama.cpp with optimal configuration based on system hardware scan.
# Supports: CPU, CUDA, ROCm, Metal, Vulkan backends
# 
# Usage: ./llama-build.sh [OPTIONS] <COMMAND>
# 
# Options:
#   --backend <type>    Specify backend: auto, metal, cuda, rocm, vulkan, cpu (default: auto)
#   --dry-run           Preview actions without executing
#   --verbose, -v       Enable verbose output
#   --help, -h         Show this help
#   --clean            Clean build files before building
#   --branch <name>    Use specific llama.cpp branch (default: master)
#   --threads <n>      Number of build threads (default: auto)
# 
# Commands:
#   build              Build Llama.cpp (default)
#   auto               Auto-detect and build (same as build)
#   build-cpu          Force CPU-only build
#   build-cuda         Force CUDA build
#   build-metal        Force Metal build
#   build-rocm         Force ROCm build
#   build-vulkan       Force Vulkan build
#   scan               Run hardware scan only
#   verify             Verify installation
#   clean              Clean build files
#   install-deps       Install required dependencies
# 
# Examples:
#   ./llama-build.sh                                     # Auto-detect and build
#   ./llama-build.sh --backend auto --verbose           # Auto with verbose
#   ./llama-build.sh --backend cuda                      # Force CUDA build
#   ./llama-build.sh --backend metal --dry-run          # Preview Metal build
#   ./llama-build.sh build-cpu                           # Force CPU build
# =============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(dirname "$SCRIPTS_DIR")"
BUILD_DIR="$RUNTIME_ROOT/.cache/llama.cpp"
INSTALL_DIR="$RUNTIME_ROOT/bin"
SOURCE_DIR="$BUILD_DIR/llama.cpp"
SCAN_RESULTS="$RUNTIME_ROOT/.cache/hardware-scan.json"
RECOMMENDATIONS="$RUNTIME_ROOT/.cache/hardware-scan-recommendations.json"
LOG_FILE="$RUNTIME_ROOT/.cache/build-log.txt"

HARDWARE_SCAN_SCRIPT="$SCRIPTS_DIR/hardware-scanner.sh"
LLAMA_REPO="https://github.com/ggerganov/llama.cpp.git"

# Default configuration
DEFAULT_BACKEND="auto"
DEFAULT_QUANT="Q4_K_M"
DEFAULT_BRANCH="master"

# Global flags
DRY_RUN=false
VERBOSE=false
FORCE_BACKEND=""
CLEAN_BUILD=false
BUILD_THREADS=""

# Ensure directories exist
mkdir -p "$BUILD_DIR" "$INSTALL_DIR"

# =============================================================================
# Logging Functions
# =============================================================================
log() {
    echo -e "${BLUE}[BUILD]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

dry_run_log() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}[DRY-RUN]${NC} $1"
    fi
}

verbose_log() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${PURPLE}[VERBOSE]${NC} $1"
    fi
}

# =============================================================================
# Dry-run mode wrapper for commands
# =============================================================================
dry_run_wrapper() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_log "Would execute: $cmd"
        dry_run_log "Description: $description"
        return 0
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        log "Executing: $cmd"
    fi
    
    # Execute the command
    eval "$cmd"
    return $?
}

# =============================================================================
# Check if already built
# =============================================================================
is_built() {
    if [[ -f "$INSTALL_DIR/llama-cli" ]] || [[ -f "$INSTALL_DIR/llama-server" ]]; then
        return 0
    fi
    return 1
}

# =============================================================================
# Get system configuration from scan
# =============================================================================
get_system_config() {
    local requested_backend="${FORCE_BACKEND:-$1}"
    local backend="$DEFAULT_BACKEND"
    local build_flags=""
    local quant="$DEFAULT_QUANT"
    
    # If backend is explicitly requested, use it
    if [[ "$requested_backend" != "" && "$requested_backend" != "auto" ]]; then
        backend="$requested_backend"
        verbose_log "Using forced backend: $backend"
    else
        # Try to load recommendations
        if [[ -f "$RECOMMENDATIONS" ]]; then
            backend=$(jq -r '.system_config.llama_cpp_build.backend // "cpu"' "$RECOMMENDATIONS" 2>/dev/null || echo "cpu")
            build_flags=$(jq -r '.system_config.llama_cpp_build.cmake_flags // ""' "$RECOMMENDATIONS" 2>/dev/null || echo "")
            quant=$(jq -r '.system_config.model_settings.default_quant // "Q4_K_M"' "$RECOMMENDATIONS" 2>/dev/null || echo "$DEFAULT_QUANT")
        elif [[ -f "$SCAN_RESULTS" ]]; then
            # Fallback: parse from scan results
            local os_name=$(jq -r '.os.name // "unknown"' "$SCAN_RESULTS")
            local architecture=$(jq -r '.os.architecture // "unknown"' "$SCAN_RESULTS")
            
            if [[ "$os_name" == "macos" && "$architecture" == "arm64" ]]; then
                backend="metal"
                build_flags="LLAMA_METAL=ON LLAMA_METAL_EMBEDDING=ON"
            elif jq -r '.nvidia.detected // false' "$SCAN_RESULTS" 2>/dev/null | grep -q "true"; then
                backend="cuda"
                build_flags="LLAMA_CUBLAS=ON"
            elif jq -r '.amd.rocm.detected // false' "$SCAN_RESULTS" 2>/dev/null | grep -q "true"; then
                backend="hip"
                build_flags="LLAMA_HIPBLAS=ON LLAMA_HIP=ON"
            elif jq -r '.vulkan.detected // false' "$SCAN_RESULTS" 2>/dev/null | grep -q "true"; then
                backend="vulkan"
                build_flags="LLAMA_VULKAN=ON"
            fi
        fi
    fi
    
    # Validate backend
    case "$backend" in
        metal|cuda|hip|rocm|vulkan|cpu|auto)
            # Valid
            ;;
        *)
            warn "Unknown backend '$backend', defaulting to cpu"
            backend="cpu"
            ;;
    esac
    
    echo "$backend $build_flags $quant"
}

# =============================================================================
# Clone or update Llama.cpp repository
# =============================================================================
clone_llama() {
    local branch="$1"
    
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_log "Would clone/update llama.cpp repository from $LLAMA_REPO (branch: $branch)"
        return 0
    fi
    
    if [[ ! -d "$SOURCE_DIR/.git" ]]; then
        log "Cloning llama.cpp repository..."
        dry_run_wrapper "git clone \"$LLAMA_REPO\" \"$SOURCE_DIR\" --branch \"$branch\" --depth 1" \
            "Clone llama.cpp repository"
        success "Repository cloned to $SOURCE_DIR"
    else
        log "Updating llama.cpp repository..."
        (cd "$SOURCE_DIR" && git pull origin "$branch" 2>&1)
        success "Repository updated"
    fi
}

# =============================================================================
# Build Llama.cpp with appropriate backend
# =============================================================================
build_llama() {
    local backend="$1"
    local build_flags="$2"
    local branch="$3"
    
    log "Building Llama.cpp with backend: $backend"
    dry_run_log "Build flags: $build_flags"
    
    # Clone repository
    clone_llama "$branch"
    
    # Create build directory
    local build_type="${backend}-build"
    local cmake_build_dir="$BUILD_DIR/$build_type"
    
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$cmake_build_dir"
    else
        dry_run_log "Would create build directory: $cmake_build_dir"
    fi
    
    # Navigate to build directory (or would navigate in dry-run)
    local old_dir="$(pwd)"
    
    if [[ "$DRY_RUN" == false ]]; then
        cd "$cmake_build_dir" || return 1
    fi
    
    # Configure CMake
    log "Configuring CMake..."
    
    local cmake_cmd="cmake $SOURCE_DIR"
    
    # Add backend-specific flags
    case "$backend" in
        "metal")
            cmake_cmd+=" -DLLAMA_METAL=ON -DLLAMA_METAL_EMBEDDING=ON"
            ;;
        "cuda")
            cmake_cmd+=" -DLLAMA_CUBLAS=ON"
            # Check for cuDNN
            if [[ -d /usr/local/cuda/include/cudnn_version.h ]]; then
                cmake_cmd+=" -DCUDNN_ROOT=/usr/local/cuda"
            fi
            ;;
        "hip")
            cmake_cmd+=" -DLLAMA_HIP=ON -DLLAMA_HIPBLAS=ON"
            ;;
        "vulkan")
            cmake_cmd+=" -DLLAMA_VULKAN=ON"
            ;;
        "cpu")
            # Check CPU features
            if echo "$build_flags" | grep -q "AVX512"; then
                cmake_cmd+=" -DLLAMA_AVX512=ON"
            fi
            if echo "$build_flags" | grep -q "AVX2"; then
                cmake_cmd+=" -DLLAMA_AVX2=ON"
            fi
            if echo "$build_flags" | grep -q "AVX"; then
                cmake_cmd+=" -DLLAMA_AVX=ON"
            fi
            # Enable native optimizations
            cmake_cmd+=" -DCMAKE_CXX_FLAGS='-march=native -O3'"
            ;;
    esac
    
    # Common flags
    cmake_cmd+=" -DCMAKE_BUILD_TYPE=Release"
    cmake_cmd+=" -DBUILD_SHARED_LIBS=OFF"
    cmake_cmd+=" -DLLAMA_BUILD_TESTS=OFF"
    cmake_cmd+=" -DLLAMA_BUILD_EXAMPLES=OFF"
    
    # Additional build flags
    if [[ "$build_flags" != "" ]]; then
        cmake_cmd+=" $build_flags"
    fi
    
    dry_run_log "CMake command: $cmake_cmd"
    
    if [[ "$DRY_RUN" == false ]]; then
        eval "$cmake_cmd" || return 1
    fi
    
    # Build
    log "Building..."
    

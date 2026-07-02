#!/bin/bash
set -e

# Build Release Script for Motive
# Creates separate DMGs for arm64 (Apple Silicon) and x86_64 (Intel)
#
# Usage:
#   ./build-release.sh                              # Build with current version
#   ./build-release.sh patch                        # Bump patch version (0.1.0 → 0.1.1)
#   ./build-release.sh minor                        # Bump minor version (0.1.0 → 0.2.0)
#   ./build-release.sh major                        # Bump major version (0.1.0 → 1.0.0)
#   ./build-release.sh --notarize                   # Build and notarize
#   ./build-release.sh --arm64-only                 # Build only for Apple Silicon
#   ./build-release.sh --x86-only                   # Build only for Intel
#
# Environment Variables (can be set in shell profile or .env file):
#   APPLE_ID          - Apple ID email for notarization
#   TEAM_ID           - Team ID (e.g., XAA75S2V8H)
#   APP_PASSWORD      - App-specific password for notarization
#   MOTIVE_NOTARIZE   - Set to "1" to enable notarization by default

APP_NAME="Motive"
SCHEME="Motive"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$PROJECT_DIR/release"
PBXPROJ="$PROJECT_DIR/$APP_NAME.xcodeproj/project.pbxproj"
STAGED_OPENCODE_PATH="$BUILD_DIR/opencode-staged"

# OpenCode version for release builds.
# Pin by default to avoid runtime API drift from "latest" causing regressions.
OPENCODE_VERSION="${OPENCODE_VERSION:-1.1.42}"
OPENCODE_ARM64_URL="https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-darwin-arm64.zip"
OPENCODE_X64_URL="https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-darwin-x64.zip"

# Settings from environment variables (with defaults)
NOTARIZE="${MOTIVE_NOTARIZE:-}"
APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"

# Build targets (default: both architectures)
BUILD_ARM64="1"
BUILD_X86="1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
config() { echo -e "${CYAN}[CONFIG]${NC} $1"; }

cleanup_staged_opencode() {
    if [ -f "$STAGED_OPENCODE_PATH" ]; then
        rm -f "$STAGED_OPENCODE_PATH" || true
    fi
}

trap cleanup_staged_opencode EXIT

# Parse command line arguments
parse_args() {
    BUMP_TYPE=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --notarize|-n)
                NOTARIZE="1"
                shift
                ;;
            --arm64-only)
                BUILD_ARM64="1"
                BUILD_X86=""
                shift
                ;;
            --x86-only|--intel-only)
                BUILD_ARM64=""
                BUILD_X86="1"
                shift
                ;;
            --apple-id)
                APPLE_ID="$2"
                shift 2
                ;;
            --team-id)
                TEAM_ID="$2"
                shift 2
                ;;
            --app-password)
                APP_PASSWORD="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            patch|minor|major)
                BUMP_TYPE="$1"
                shift
                ;;
            *)
                error "Unknown option: $1 (use --help for usage)"
                ;;
        esac
    done
}

show_help() {
    echo "Usage: $0 [patch|minor|major] [OPTIONS]"
    echo ""
    echo "Version bump:"
    echo "  patch                     Bump patch version (0.1.0 → 0.1.1)"
    echo "  minor                     Bump minor version (0.1.0 → 0.2.0)"
    echo "  major                     Bump major version (0.1.0 → 1.0.0)"
    echo ""
    echo "Build options:"
    echo "  --arm64-only              Build only for Apple Silicon"
    echo "  --x86-only, --intel-only  Build only for Intel"
    echo ""
    echo "Notarization options:"
    echo "  --notarize, -n            Enable notarization"
    echo "  --apple-id EMAIL          Apple ID for notarization"
    echo "  --team-id TEAM            Team ID (e.g., XAA75S2V8H)"
    echo "  --app-password PASSWORD   App-specific password"
    echo ""
    echo "Environment variables (set these to avoid prompts):"
    echo "  APPLE_ID                  Apple ID email"
    echo "  TEAM_ID                   Team ID"
    echo "  APP_PASSWORD              App-specific password"
    echo "  MOTIVE_NOTARIZE=1         Enable notarization by default"
    echo ""
    echo "Examples:"
    echo "  $0                                    Build without notarization"
    echo "  $0 patch --notarize                   Bump patch and notarize"
    echo "  $0 --arm64-only --notarize            Build only arm64 and notarize"
    echo ""
    echo "Tip: Add to ~/.zshrc or ~/.bashrc for persistent config:"
    echo "  export APPLE_ID='your@email.com'"
    echo "  export TEAM_ID='XAA75S2V8H'"
    echo "  export APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'"
    echo "  export MOTIVE_NOTARIZE=1"
}

# Display current configuration
show_config() {
    echo ""
    config "Build Configuration:"
    config "  Notarization:  $([ "$NOTARIZE" = "1" ] && echo "✅ Enabled" || echo "❌ Disabled")"
    config "  OpenCode:      v${OPENCODE_VERSION}"
    config "  Architectures: $([ "$BUILD_ARM64" = "1" ] && echo "arm64 ")$([ "$BUILD_X86" = "1" ] && echo "x86_64")"
    if [ "$NOTARIZE" = "1" ]; then
        config "  Apple ID:      $([ -n "$APPLE_ID" ] && echo "${APPLE_ID}" || echo "(will prompt)")"
        config "  Team ID:       $([ -n "$TEAM_ID" ] && echo "${TEAM_ID}" || echo "(will prompt)")"
        config "  App Password:  $([ -n "$APP_PASSWORD" ] && echo "********" || echo "(will prompt)")"
    fi
    echo ""
}

# Prompt for notarization credentials if needed
prompt_notarization_credentials() {
    if [ "$NOTARIZE" != "1" ]; then
        return
    fi
    
    if [ -z "$APPLE_ID" ]; then
        read -p "Apple ID (email): " APPLE_ID
    fi
    
    if [ -z "$TEAM_ID" ]; then
        # Try to get from Developer ID certificate
        local detected_team=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*(\([A-Z0-9]*\)).*/\1/')
        if [ -n "$detected_team" ]; then
            info "Detected Team ID: $detected_team"
            read -p "Team ID [$detected_team]: " input_team
            TEAM_ID="${input_team:-$detected_team}"
        else
            read -p "Team ID: " TEAM_ID
        fi
    fi
    
    if [ -z "$APP_PASSWORD" ]; then
        echo "Get app-specific password from: https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
        read -sp "App-specific password: " APP_PASSWORD
        echo ""
    fi
    
    if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$APP_PASSWORD" ]; then
        error "All credentials are required for notarization"
    fi
}

# Get entitlements path
get_entitlements_path() {
    echo "$PROJECT_DIR/$APP_NAME/Entitlements/MotiveRelease.entitlements"
}

# Clean previous builds
clean() {
    log "Cleaning previous builds..."
    if [ -d "$BUILD_DIR" ]; then
        chflags -R nouchg "$BUILD_DIR" 2>/dev/null || true
        chmod -R u+w "$BUILD_DIR" 2>/dev/null || true
        rm -rf "$BUILD_DIR"
    fi
    if [ -d "$RELEASE_DIR" ]; then
        chflags -R nouchg "$RELEASE_DIR" 2>/dev/null || true
        chmod -R u+w "$RELEASE_DIR" 2>/dev/null || true
        rm -rf "$RELEASE_DIR"
    fi
    mkdir -p "$BUILD_DIR"
    mkdir -p "$RELEASE_DIR"
}

# Download OpenCode binary for specific architecture
download_opencode() {
    local arch=$1
    local url=$2
    local zipfile="$BUILD_DIR/opencode-$arch.zip"
    local dest="$BUILD_DIR/opencode-$arch"
    
    log "Downloading OpenCode for $arch..."
    curl -L -f "$url" -o "$zipfile" || error "Failed to download OpenCode for $arch"
    
    log "Extracting OpenCode for $arch..."
    unzip -o "$zipfile" -d "$BUILD_DIR"
    mv "$BUILD_DIR/opencode" "$dest"
    rm "$zipfile"
    
    chmod +x "$dest"
    log "Downloaded and extracted OpenCode for $arch"
}

# Build app for specific architecture
build_app() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local opencode_path="$BUILD_DIR/opencode-$arch"
    
    log "Building $APP_NAME for $arch..."

    if [ ! -f "$opencode_path" ]; then
        error "OpenCode binary for $arch not found at $opencode_path (download step likely failed)"
    fi

    # Stage OpenCode into the path already whitelisted by Xcode script sandbox
    # (SCRIPT_INPUT_FILE_1 = Motive/Resources/opencode).
    cp -f "$opencode_path" "$STAGED_OPENCODE_PATH"
    chmod +x "$STAGED_OPENCODE_PATH"

    xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -arch "$arch" \
        -derivedDataPath "$build_path" \
        ONLY_ACTIVE_ARCH=NO \
        MACOSX_DEPLOYMENT_TARGET=15.0 \
        ENABLE_USER_SCRIPT_SANDBOXING=NO \
        build
    
    log "Build complete for $arch"
}

# Copy OpenCode binary into app bundle
inject_opencode() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local app_path="$build_path/Build/Products/Release/$APP_NAME.app"
    local contents_path="$app_path/Contents"
    local bundle_opencode="$contents_path/opencode"
    local opencode_src="$BUILD_DIR/opencode-$arch"
    
    log "Verifying bundled OpenCode for $arch..."
    
    if [ ! -d "$app_path" ]; then
        error "App not found at $app_path"
    fi

    # Xcode Run Script should already copy opencode into Contents/opencode.
    # Keep fallback copy for resilience when running custom build flows.
    if [ ! -f "$bundle_opencode" ]; then
        warn "OpenCode missing after build, applying fallback copy to Contents/opencode"
        cp "$opencode_src" "$bundle_opencode"
        chmod +x "$bundle_opencode"
    fi

    log "OpenCode present at $bundle_opencode"
}

# Re-sign the entire app bundle
sign_app() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local app_path="$build_path/Build/Products/Release/$APP_NAME.app"
    local entitlements_path=$(get_entitlements_path)
    
    log "Signing app bundle for $arch..."
    log "Using entitlements: $(basename "$entitlements_path")"
    
    # Check if Developer ID is available
    local signing_identity=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    
    if [ -n "$signing_identity" ]; then
        log "Signing with Developer ID: $signing_identity"
        
        # Sign all embedded binaries first (inside-out signing)
        local resources_path="$app_path/Contents/Resources"
        local contents_path="$app_path/Contents"
        
        # Sign OpenCode binary (support both locations for compatibility)
        for opencode_path in "$contents_path/opencode" "$resources_path/opencode"; do
            if [ -f "$opencode_path" ]; then
                log "Signing OpenCode binary at $(basename "$(dirname "$opencode_path")")/$(basename "$opencode_path")..."
                codesign --force --options runtime --timestamp \
                    --sign "$signing_identity" "$opencode_path"
            fi
        done
        
        # Sign browser-use-sidecar (Python bundle)
        # CRITICAL: Must include entitlements with disable-library-validation
        # because PyInstaller extracts libpython3.12.dylib (signed by Python.org)
        # at runtime, and Hardened Runtime would reject the different Team ID.
        local sidecar_path="$resources_path/browser-use-sidecar"
        local sidecar_entitlements="$PROJECT_DIR/$APP_NAME/Entitlements/Sidecar.entitlements"
        if [ -d "$sidecar_path" ]; then
            log "Signing browser-use-sidecar (directory)..."
            # Sign all binaries inside the sidecar directory
            find "$sidecar_path" -type f -perm +111 | while read binary; do
                codesign --force --options runtime --timestamp \
                    --entitlements "$sidecar_entitlements" \
                    --sign "$signing_identity" "$binary" 2>/dev/null || true
            done
            # Sign .so and .dylib files
            find "$sidecar_path" -type f \( -name "*.so" -o -name "*.dylib" \) | while read lib; do
                codesign --force --options runtime --timestamp \
                    --entitlements "$sidecar_entitlements" \
                    --sign "$signing_identity" "$lib" 2>/dev/null || true
            done
            # Sign the main sidecar binary/directory
            codesign --force --options runtime --timestamp \
                --entitlements "$sidecar_entitlements" \
                --sign "$signing_identity" "$sidecar_path" 2>/dev/null || true
        elif [ -f "$sidecar_path" ]; then
            log "Signing browser-use-sidecar (single file)..."
            codesign --force --options runtime --timestamp \
                --entitlements "$sidecar_entitlements" \
                --sign "$signing_identity" "$sidecar_path"
        fi
        
        # Sign any other binaries in Resources
        find "$resources_path" -maxdepth 1 -type f -perm +111 ! -name "opencode" ! -name "browser-use-sidecar" | while read binary; do
            log "Signing $(basename "$binary")..."
            codesign --force --options runtime --timestamp \
                --sign "$signing_identity" "$binary" 2>/dev/null || true
        done
        
        # Sign the app bundle with entitlements
        log "Signing main app bundle..."
        codesign --force --deep --options runtime --timestamp \
            --entitlements "$entitlements_path" \
            --sign "$signing_identity" \
            "$app_path"
        
        log "App signed with Developer ID for $arch"
    else
        warn "No Developer ID found, using ad-hoc signature (distribution not possible)"
        codesign --force --deep --sign - "$app_path"
        log "App signed with ad-hoc signature for $arch"
    fi
}

# Smoke test bundled opencode server + async prompt path.
smoke_test_bundled_opencode() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local app_path="$build_path/Build/Products/Release/$APP_NAME.app"
    local opencode_bin="$app_path/Contents/opencode"
    local plugin_entry="$app_path/Contents/Resources/Plugins/motive-memory/src/index.ts"
    local smoke_root="$BUILD_DIR/smoke-$arch"
    local smoke_workspace="$smoke_root/workspace"
    local smoke_config="$smoke_root/opencode.json"
    local smoke_log="$smoke_root/server.log"
    local smoke_port

    log "Running smoke test for $arch bundle..."

    [ -f "$opencode_bin" ] || error "Smoke test failed: bundled opencode missing at $opencode_bin"
    [ -f "$plugin_entry" ] || error "Smoke test failed: memory plugin entry missing at $plugin_entry"

    rm -rf "$smoke_root"
    mkdir -p "$smoke_workspace"
    smoke_port=$([ "$arch" = "arm64" ] && echo "47100" || echo "47101")

    cat > "$smoke_config" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "default_agent": "agent",
  "enabled_providers": ["openai"],
  "permission": {
    "bash": "allow",
    "edit": "allow",
    "external_directory": "allow",
    "glob": "allow",
    "grep": "allow",
    "list": "allow",
    "question": "allow",
    "read": "allow",
    "task": "allow",
    "webfetch": "allow",
    "websearch": "allow"
  },
  "agent": {
    "agent": {
      "description": "smoke test agent",
      "prompt": "smoke test",
      "mode": "primary",
      "permission": {
        "bash": "allow",
        "edit": "allow",
        "external_directory": "allow",
        "glob": "allow",
        "grep": "allow",
        "list": "allow",
        "question": "allow",
        "read": "allow",
        "task": "allow",
        "webfetch": "allow",
        "websearch": "allow"
      }
    }
  },
  "plugin": ["file://$plugin_entry"]
}
EOF

    OPENCODE_CONFIG="$smoke_config" OPENCODE_CONFIG_DIR="$smoke_root" \
        MOTIVE_WORKSPACE="$smoke_workspace" "$opencode_bin" serve --port "$smoke_port" --hostname 127.0.0.1 \
        > "$smoke_log" 2>&1 &
    local server_pid=$!

    cleanup_smoke() {
        kill "$server_pid" >/dev/null 2>&1 || true
    }
    trap cleanup_smoke RETURN

    local started=""
    for _ in $(seq 1 30); do
        if grep -q "listening on http://127.0.0.1:$smoke_port" "$smoke_log" 2>/dev/null; then
            started="1"
            break
        fi
        sleep 0.5
    done
    [ -n "$started" ] || error "Smoke test failed: opencode server did not start ($smoke_log)"

    python3 - <<PY || error "Smoke test failed: prompt_async hello did not return 204"
import json
import urllib.request
base = "http://127.0.0.1:$smoke_port"
headers = {"Content-Type": "application/json", "x-opencode-directory": "$smoke_workspace"}
req = urllib.request.Request(base + "/session", data=b"{}", headers=headers, method="POST")
with urllib.request.urlopen(req, timeout=10) as resp:
    session = json.loads(resp.read().decode())
sid = session["id"]
body = json.dumps({"parts":[{"type":"text","text":"hello"}], "agent":"agent"}).encode()
req2 = urllib.request.Request(base + f"/session/{sid}/prompt_async", data=body, headers=headers, method="POST")
with urllib.request.urlopen(req2, timeout=20) as resp:
    if resp.status != 204:
        raise SystemExit(f"unexpected status {resp.status}")
PY

    log "Smoke test passed for $arch"
}

# Notarize the app
notarize_app() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local app_path="$build_path/Build/Products/Release/$APP_NAME.app"
    
    if [ "$NOTARIZE" != "1" ]; then
        info "Skipping notarization (use --notarize to enable)"
        return
    fi
    
    log "Creating ZIP for notarization..."
    local zip_path="$BUILD_DIR/$APP_NAME-$arch-notarize.zip"
    ditto -c -k --keepParent "$app_path" "$zip_path"
    
    log "Submitting to Apple for notarization (this may take a few minutes)..."
    local notarize_output
    notarize_output=$(xcrun notarytool submit "$zip_path" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait 2>&1)
    local notarize_status=$?
    
    echo "$notarize_output"
    
    # Check if notarization was accepted
    if echo "$notarize_output" | grep -q "status: Accepted"; then
        log "Notarization accepted! Stapling ticket..."
        
        # Try stapling with retries (Apple CDN may need time to sync)
        local staple_success=false
        for i in 1 2 3; do
            if xcrun stapler staple "$app_path" 2>/dev/null; then
                staple_success=true
                break
            fi
            if [ $i -lt 3 ]; then
                warn "Staple attempt $i failed, waiting 30 seconds..."
                sleep 30
            fi
        done
        
        if [ "$staple_success" = true ]; then
            log "Notarization and stapling complete for $arch"
        else
            warn "Stapling failed (notarization succeeded). Users will need internet for first launch."
            warn "You can manually staple later: xcrun stapler staple \"$app_path\""
        fi
    elif [ $notarize_status -eq 0 ]; then
        # Exit code 0 but not "Accepted" - check for Invalid
        if echo "$notarize_output" | grep -q "status: Invalid"; then
            error "Notarization rejected for $arch. Run: xcrun notarytool log <submission-id> --apple-id $APPLE_ID --team-id $TEAM_ID --password <password>"
        else
            warn "Notarization status unclear for $arch"
        fi
    else
        error "Notarization submission failed for $arch"
    fi
    
    rm -f "$zip_path"
}

# Create DMG
create_dmg() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local app_path="$build_path/Build/Products/Release/$APP_NAME.app"
    local dmg_name="$APP_NAME-$arch.dmg"
    local dmg_path="$RELEASE_DIR/$dmg_name"
    local staging_dir="$BUILD_DIR/dmg-staging-$arch"
    
    log "Creating DMG for $arch..."
    
    # Create staging directory
    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"
    
    # Copy app
    cp -R "$app_path" "$staging_dir/"
    
    # Create symbolic link to Applications
    ln -s /Applications "$staging_dir/Applications"
    
    # Create DMG
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$staging_dir" \
        -ov -format UDZO \
        "$dmg_path"
    
    # Clean up
    rm -rf "$staging_dir"
    
    log "DMG created: $dmg_path"
    
    # Notarize DMG if enabled
    if [ "$NOTARIZE" == "1" ]; then
        log "Submitting DMG for notarization..."
        xcrun notarytool submit "$dmg_path" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD" \
            --wait
        
        if [ $? -eq 0 ]; then
            xcrun stapler staple "$dmg_path"
            log "DMG notarization complete"
        else
            warn "DMG notarization failed (app still notarized)"
        fi
    fi
}

# Get current version from project.pbxproj
get_version() {
    local version=$(grep "MARKETING_VERSION" "$PBXPROJ" | head -1 | sed 's/.*= *\([^;]*\);/\1/' | tr -d ' ')
    echo "${version:-0.1.0}"
}

# Bump version based on type (patch/minor/major)
bump_version() {
    local current=$1
    local bump_type=$2
    
    # Parse version components
    local major=$(echo "$current" | cut -d. -f1)
    local minor=$(echo "$current" | cut -d. -f2)
    local patch=$(echo "$current" | cut -d. -f3)
    
    # Default to 0 if not present
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}
    
    case $bump_type in
        patch)
            patch=$((patch + 1))
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        *)
            error "Invalid bump type: $bump_type (use: patch, minor, major)"
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Update version in project.pbxproj
set_version() {
    local new_version=$1
    
    log "Updating version to $new_version in project.pbxproj..."
    
    # Replace all MARKETING_VERSION occurrences
    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $new_version;/g" "$PBXPROJ"
    
    log "Version updated to $new_version"
}

# Main build process
main() {
    # Parse command line arguments
    parse_args "$@"
    
    log "Starting release build for $APP_NAME"
    log "Project directory: $PROJECT_DIR"
    
    # Show configuration
    show_config
    
    # Prompt for notarization credentials if needed
    prompt_notarization_credentials
    
    # Get current version
    CURRENT_VERSION=$(get_version)
    info "Current version: $CURRENT_VERSION"
    
    # Bump version if requested
    if [ -n "$BUMP_TYPE" ]; then
        VERSION=$(bump_version "$CURRENT_VERSION" "$BUMP_TYPE")
        set_version "$VERSION"
        log "Version bumped: $CURRENT_VERSION → $VERSION ($BUMP_TYPE)"
    else
        VERSION="$CURRENT_VERSION"
        info "Building with current version: $VERSION"
    fi
    
    # Clean
    clean
    
    # Download OpenCode binaries based on target architectures
    if [ "$BUILD_ARM64" = "1" ]; then
        download_opencode "arm64" "$OPENCODE_ARM64_URL"
    fi
    if [ "$BUILD_X86" = "1" ]; then
        download_opencode "x86_64" "$OPENCODE_X64_URL"
    fi
    
    # Build for arm64 (Apple Silicon)
    if [ "$BUILD_ARM64" = "1" ]; then
        log "=== Building for Apple Silicon (arm64) ==="
        build_app "arm64"
        inject_opencode "arm64"
        smoke_test_bundled_opencode "arm64"
        sign_app "arm64"
        notarize_app "arm64"
        create_dmg "arm64"
    fi
    
    # Build for x86_64 (Intel)
    if [ "$BUILD_X86" = "1" ]; then
        log "=== Building for Intel (x86_64) ==="
        build_app "x86_64"
        inject_opencode "x86_64"
        smoke_test_bundled_opencode "x86_64"
        sign_app "x86_64"
        notarize_app "x86_64"
        create_dmg "x86_64"
    fi
    
    log "=== Build Complete ==="
    log "Release files:"
    ls -la "$RELEASE_DIR"
    
    echo ""
    info "Build summary:"
    info "  Notarization:  $([ "$NOTARIZE" = "1" ] && echo "✅ Done" || echo "❌ Skipped")"
}

# Run
main "$@"

#!/usr/bin/env bash
set -euo pipefail

REPO="ZhengLai98/claude-code"
VERSION="${CCB_VERSION:-latest}"
INSTALL_DIR="${CCB_INSTALL_DIR:-/usr/local/bin}"
LIB_DIR="${CCB_LIB_DIR:-}"
BASE_URL_OVERRIDE="${CCB_BASE_URL:-}"

usage() {
  cat <<'EOF'
Install ccb from GitHub Releases.

Usage:
  install.sh [--version <tag|latest>] [--install-dir <dir>] [--lib-dir <dir>]

Environment:
  CCB_VERSION      Release tag to install, e.g. v2.6.14. Defaults to latest.
  CCB_INSTALL_DIR  Install directory. Defaults to /usr/local/bin.
  CCB_LIB_DIR      Directory for the unpacked release package. Defaults to <install-parent>/lib/ccb.
  CCB_BASE_URL     Override release asset base URL for testing or mirrors.

Examples:
  curl -fsSL https://github.com/ZhengLai98/claude-code/releases/latest/download/install.sh | bash
  curl -fsSL https://github.com/ZhengLai98/claude-code/releases/download/v2.6.14/install.sh | bash -s -- --version v2.6.14
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --lib-dir)
      LIB_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Missing version value" >&2
  exit 1
fi

if [[ -z "$INSTALL_DIR" ]]; then
  echo "Missing install directory" >&2
  exit 1
fi

if [[ -z "$LIB_DIR" ]]; then
  LIB_DIR="$(dirname "$INSTALL_DIR")/lib/ccb"
fi

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd tar

case "$(uname -s)" in
  Darwin)
    os="darwin"
    ;;
  Linux)
    os="linux"
    ;;
  *)
    echo "Unsupported OS: $(uname -s). Please download the matching release archive manually." >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64)
    arch="arm64"
    ;;
  x86_64|amd64)
    arch="x64"
    ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

target="${os}-${arch}"
asset="ccb-${target}.tar.gz"
pkg_dir="ccb-${target}"

if [[ -n "$BASE_URL_OVERRIDE" ]]; then
  base_url="${BASE_URL_OVERRIDE%/}"
elif [[ "$VERSION" == "latest" ]]; then
  base_url="https://github.com/${REPO}/releases/latest/download"
else
  base_url="https://github.com/${REPO}/releases/download/${VERSION}"
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

archive_path="${tmp_dir}/${asset}"
checksum_path="${archive_path}.sha256"

echo "Downloading ${asset} from ${VERSION}..."
curl -fsSL --retry 3 --retry-delay 2 "${base_url}/${asset}" -o "$archive_path"

echo "Downloading checksum..."
curl -fsSL --retry 3 --retry-delay 2 "${base_url}/${asset}.sha256" -o "$checksum_path"

echo "Verifying checksum..."
if command -v shasum >/dev/null 2>&1; then
  (cd "$tmp_dir" && shasum -a 256 -c "${asset}.sha256")
elif command -v sha256sum >/dev/null 2>&1; then
  (cd "$tmp_dir" && sha256sum -c "${asset}.sha256")
else
  echo "Neither shasum nor sha256sum is available; skipping checksum verification." >&2
fi

echo "Extracting..."
tar -xzf "$archive_path" -C "$tmp_dir"

package_path="${tmp_dir}/${pkg_dir}"
binary_path="${package_path}/ccb"
if [[ ! -d "$package_path" || ! -x "$binary_path" ]]; then
  echo "Expected executable not found: ${pkg_dir}/ccb" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR" 2>/dev/null || true
mkdir -p "$(dirname "$LIB_DIR")" 2>/dev/null || true

shim_path="${tmp_dir}/ccb-shim"
cat > "$shim_path" <<EOF
#!/usr/bin/env bash
exec "${LIB_DIR}/ccb" "\$@"
EOF

if [[ -w "$INSTALL_DIR" && -w "$(dirname "$LIB_DIR")" ]]; then
  rm -rf "$LIB_DIR"
  mkdir -p "$LIB_DIR"
  cp -R "${package_path}/." "$LIB_DIR/"
  chmod +x "${LIB_DIR}/ccb"
  install -m 755 "$shim_path" "${INSTALL_DIR}/ccb"
else
  need_cmd sudo
  sudo rm -rf "$LIB_DIR"
  sudo mkdir -p "$LIB_DIR" "$INSTALL_DIR"
  sudo cp -R "${package_path}/." "$LIB_DIR/"
  sudo chmod +x "${LIB_DIR}/ccb"
  sudo install -m 755 "$shim_path" "${INSTALL_DIR}/ccb"
fi

echo "Installed ccb package to ${LIB_DIR}"
echo "Installed ccb command to ${INSTALL_DIR}/ccb"
"${INSTALL_DIR}/ccb" --version

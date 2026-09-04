#!/bin/bash
# Deploy su_mcp extension to Windows SketchUp 2026 plugins directory via SSH.
#
# Run from inside the devcontainer:
#   ./deploy-windows.sh
#
# Uses the existing blender-key SSH credentials. We can't scp directly because
# scp double-escapes the spaces in "SketchUp 2026" — instead we base64-pipe
# each file through ssh + a small PowerShell snippet that writes the bytes.

set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-/workspaces/mb-dev-workspace/.ssh/blender-key}"
WINDOWS_USER="${WINDOWS_USER:-kstratford}"
WINDOWS_HOST="${WINDOWS_HOST:-host.docker.internal}"
SU_VERSION="${SU_VERSION:-2026}"

PLUGINS_DIR="C:\\Users\\${WINDOWS_USER}\\AppData\\Roaming\\SketchUp\\SketchUp ${SU_VERSION}\\SketchUp\\Plugins"

ssh_cmd() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${WINDOWS_USER}@${WINDOWS_HOST}" "$@"
}

# Upload a single file by base64-piping through PowerShell.
# $1 = local source path
# $2 = remote destination path (Windows-style with backslashes)
upload_file() {
  local src="$1"
  local dest="$2"
  echo "  -> $dest"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${WINDOWS_USER}@${WINDOWS_HOST}" \
    "powershell -Command \"[IO.File]::WriteAllBytes('${dest}', [Convert]::FromBase64String([Console]::In.ReadToEnd()))\"" \
    < <(base64 -w0 "$src")
}

echo "Deploying su_mcp from $SRC to ${WINDOWS_USER}@${WINDOWS_HOST}:${PLUGINS_DIR}"

# Make sure the target directory exists.
ssh_cmd "if not exist \"${PLUGINS_DIR}\\su_mcp\" mkdir \"${PLUGINS_DIR}\\su_mcp\""

# Clean up any stale signature artifacts from a previous deployment.
ssh_cmd "del /Q \"${PLUGINS_DIR}\\su_mcp.rbs\" 2>nul" || true
ssh_cmd "del /Q \"${PLUGINS_DIR}\\su_mcp\\*.rbs\" 2>nul" || true
ssh_cmd "del /Q \"${PLUGINS_DIR}\\su_mcp\\signature.sig\" 2>nul" || true
ssh_cmd "del /Q \"${PLUGINS_DIR}\\su_mcp\\signing_cert.pem\" 2>nul" || true

# Copy the loader stub
upload_file "$SRC/su_mcp.rb" "${PLUGINS_DIR}\\su_mcp.rb"

# Copy the extension files
for f in main.rb woodworking.rb package.rb extension.json; do
  upload_file "$SRC/su_mcp/$f" "${PLUGINS_DIR}\\su_mcp\\$f"
done

echo ""
echo "Deployed successfully."
echo ""
echo "Next: open SketchUp Pro 2026 on Windows, then in the Ruby Console run:"
echo '  load "su_mcp/woodworking.rb"; load "su_mcp/main.rb"'
echo "  SU_MCP::Server.new.start"
echo ""
echo "You should see: 'MCP: Server created on port 9877'"

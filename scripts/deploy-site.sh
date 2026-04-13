#!/usr/bin/env bash
set -euo pipefail

# Deploy the website from docs/ over SSH + rsync.
# Defaults can be overridden via env vars:
#   DEPLOY_HOST
#   DEPLOY_USER
#   DEPLOY_PATH
# Optional env vars:
#   DEPLOY_PORT   e.g. 22 (default: 22)
#   DRY_RUN       set to 1 for preview mode
#   SITE_URL      defaults to https://send.moi
#   DEPLOY_IDENTITY_FILE

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_ROOT="${REPO_ROOT}/docs"

DEPLOY_HOST="${DEPLOY_HOST:-ssh.suckahs.org}"
DEPLOY_USER="${DEPLOY_USER:-suckahs}"
DEPLOY_PATH="${DEPLOY_PATH:-/home/suckahs/public_html/sendmoi}"

DEPLOY_PORT="${DEPLOY_PORT:-22}"
DRY_RUN="${DRY_RUN:-0}"
SITE_URL="${SITE_URL:-https://send.moi}"
DEPLOY_IDENTITY_FILE="${DEPLOY_IDENTITY_FILE:-}"

RSYNC_ARGS=(
  -avz
  --delete
  --exclude .git/
  --exclude .DS_Store
)

if [[ "$DRY_RUN" == "1" ]]; then
  RSYNC_ARGS+=(--dry-run)
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sendmoi-deploy.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp "${SITE_ROOT}/index.html" "$STAGING_DIR/"
cp -R "${SITE_ROOT}/privacy" "$STAGING_DIR/"
cp -R "${SITE_ROOT}/terms" "$STAGING_DIR/"
cp -R "${SITE_ROOT}/accessibility" "$STAGING_DIR/"
cp -R "${SITE_ROOT}/assets" "$STAGING_DIR/"

"${REPO_ROOT}/scripts/set-site-url.sh" "$SITE_URL" "$STAGING_DIR"

light_cache_bust="$(shasum -a 256 "$STAGING_DIR/assets/images/sendmoi/app-icon-light.png" | awk '{print substr($1, 1, 12)}')"
dark_cache_bust="$(shasum -a 256 "$STAGING_DIR/assets/images/sendmoi/app-icon-dark.png" | awk '{print substr($1, 1, 12)}')"
fallback_cache_bust="$(shasum -a 256 "$STAGING_DIR/assets/images/sendmoi/app-icon.png" | awk '{print substr($1, 1, 12)}')"

PAGE_FILES=(
  "$STAGING_DIR/index.html"
  "$STAGING_DIR/privacy/index.html"
  "$STAGING_DIR/terms/index.html"
  "$STAGING_DIR/accessibility/index.html"
)

perl -0pi -e "s#(app-icon-light\\.png)(?:\\?v=[^\"]+)?#\${1}?v=${light_cache_bust}#g" "${PAGE_FILES[@]}"
perl -0pi -e "s#(app-icon-dark\\.png)(?:\\?v=[^\"]+)?#\${1}?v=${dark_cache_bust}#g" "${PAGE_FILES[@]}"
perl -0pi -e "s#(app-icon\\.png)(?:\\?v=[^\"]+)?#\${1}?v=${fallback_cache_bust}#g" "${PAGE_FILES[@]}"

image_url="${SITE_URL%/}/assets/images/sendmoi/app-icon-light.png?v=${light_cache_bust}"
perl -0pi -e "s#<meta property=\"og:image\" content=\"[^\"]*\" />#<meta property=\"og:image\" content=\"${image_url}\" />#g" "$STAGING_DIR/index.html"
perl -0pi -e "s#<meta property=\"og:image:secure_url\" content=\"[^\"]*\" />#<meta property=\"og:image:secure_url\" content=\"${image_url}\" />#g" "$STAGING_DIR/index.html"
perl -0pi -e "s#<meta name=\"twitter:image\" content=\"[^\"]*\" />#<meta name=\"twitter:image\" content=\"${image_url}\" />#g" "$STAGING_DIR/index.html"

echo "Using staged asset cache-bust versions: app-icon-light.png?v=${light_cache_bust}, app-icon-dark.png?v=${dark_cache_bust}, app-icon.png?v=${fallback_cache_bust}"

REMOTE="${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH%/}/"
SSH_CMD=(
  ssh
  -p "$DEPLOY_PORT"
  -o IdentityAgent=none
  -o IdentitiesOnly=yes
  -o PreferredAuthentications=publickey
)

if [[ -n "$DEPLOY_IDENTITY_FILE" ]]; then
  SSH_CMD+=(-i "$DEPLOY_IDENTITY_FILE")
elif [[ -f "${HOME}/.ssh/sendmoi_deploy" ]]; then
  SSH_CMD+=(-i "${HOME}/.ssh/sendmoi_deploy")
elif [[ -f "${HOME}/.ssh/aiquota_deploy_nopass" ]]; then
  SSH_CMD+=(-i "${HOME}/.ssh/aiquota_deploy_nopass")
elif [[ -f "${HOME}/.ssh/aiquota_deploy" ]]; then
  SSH_CMD+=(-i "${HOME}/.ssh/aiquota_deploy")
fi

printf -v RSYNC_SSH_CMD '%q ' "${SSH_CMD[@]}"
RSYNC_SSH_CMD="${RSYNC_SSH_CMD% }"

"${SSH_CMD[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" "mkdir -p '${DEPLOY_PATH%/}'"

rsync "${RSYNC_ARGS[@]}" -e "$RSYNC_SSH_CMD" \
  "$STAGING_DIR/index.html" \
  "$STAGING_DIR/privacy" \
  "$STAGING_DIR/terms" \
  "$STAGING_DIR/accessibility" \
  "$STAGING_DIR/assets" \
  "$REMOTE"

echo "Deploy complete -> $REMOTE"

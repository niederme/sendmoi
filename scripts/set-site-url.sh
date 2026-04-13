#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <site-url> [site-root]" >&2
  exit 1
fi

site_url="${1%/}"
site_root="${2:-.}"

index_url="${site_url}/"
privacy_url="${site_url}/privacy/"
terms_url="${site_url}/terms/"
accessibility_url="${site_url}/accessibility/"

index_page="${site_root%/}/index.html"
privacy_page="${site_root%/}/privacy/index.html"
terms_page="${site_root%/}/terms/index.html"
accessibility_page="${site_root%/}/accessibility/index.html"

perl -0pi -e "s#<link rel=\"canonical\" href=\"[^\"]*\" />#<link rel=\"canonical\" href=\"${index_url}\" />#g" "$index_page"
perl -0pi -e "s#<meta property=\"og:url\" content=\"[^\"]*\" />#<meta property=\"og:url\" content=\"${index_url}\" />#g" "$index_page"
perl -0pi -e "s#<meta name=\"twitter:url\" content=\"[^\"]*\" />#<meta name=\"twitter:url\" content=\"${index_url}\" />#g" "$index_page"

perl -0pi -e "s#<link rel=\"canonical\" href=\"[^\"]*\" />#<link rel=\"canonical\" href=\"${privacy_url}\" />#g" "$privacy_page"
perl -0pi -e "s#<link rel=\"canonical\" href=\"[^\"]*\" />#<link rel=\"canonical\" href=\"${terms_url}\" />#g" "$terms_page"
perl -0pi -e "s#<link rel=\"canonical\" href=\"[^\"]*\" />#<link rel=\"canonical\" href=\"${accessibility_url}\" />#g" "$accessibility_page"

echo "Updated canonical/social URLs for ${site_url} in ${site_root}"

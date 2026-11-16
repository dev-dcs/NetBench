#!/usr/bin/env bash
# release helper for NetBench - @Dev_DcS
#   scripts/release.sh bump [patch|minor|major]   bump module.prop version
#   scripts/release.sh json                        print update.json
#   scripts/release.sh publish <zip>               (CI) GitHub release + update.json
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
PROP=module/module.prop
REPO=${GITHUB_REPOSITORY:-dev-dcs/NetBench}

ver() { sed -n 's/^version=v//p' "$PROP"; }
json() {
  local v; v=$(ver)
  cat <<EOF
{
  "version": "v$v",
  "versionCode": $(sed -n 's/^versionCode=//p' "$PROP"),
  "zipUrl": "https://github.com/$REPO/releases/download/v$v/NetBench-v$v.zip",
  "changelog": "https://raw.githubusercontent.com/$REPO/main/CHANGELOG.md"
}
EOF
}

case ${1:-} in
bump)
  IFS=. read -r ma mi pa <<< "$(ver)"
  case ${2:-patch} in
    major) ma=$((ma+1)); mi=0; pa=0 ;;
    minor) mi=$((mi+1)); pa=0 ;;
    patch) pa=$((pa+1)) ;;
    *) echo "patch|minor|major" >&2; exit 1 ;;
  esac
  v=$ma.$mi.$pa; code=$((ma*10000 + mi*100 + pa))
  sed -i "s/^version=.*/version=v$v/; s/^versionCode=.*/versionCode=$code/" "$PROP"
  echo "v$v ($code)"
  ;;
json) json ;;
publish)
  zip=${2:?zip path}; v=$(ver); tag=v$v
  notes=$(awk -v h="## v$v" '$0==h{on=1;next} /^## /&&on{exit} on' CHANGELOG.md)
  gh release create "$tag" "$zip" --title "NetBench $tag" --notes "${notes:-$tag}"
  git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
  git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
  br=$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)
  git fetch -q origin "$br"; git checkout -q -B "$br" "origin/$br"
  json > update.json; git add update.json
  git commit -q -m "update.json: $tag" && git push -q origin "$br" || echo "update.json unchanged"
  ;;
*) sed -n '2,6p' "$0"; exit 1 ;;
esac

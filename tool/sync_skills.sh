#!/usr/bin/env bash
#
# Vendors the PowerSync agent skill from powersync-ja/agent-skills into
# packages/powersync/skills/, where `dart run skills@ get` finds it for users of
# this package.
#
# Usage:
#   tool/sync_skills.sh            # sync from the latest agent-skills release
#   tool/sync_skills.sh v1.4.0     # sync from a specific release tag
#   tool/sync_skills.sh --check    # re-sync the recorded release into a temp
#                                  # dir and fail if the vendored files differ
#
# Set GH_TOKEN to avoid GitHub API rate limits (done automatically in CI).
set -euo pipefail

SOURCE_REPO="powersync-ja/agent-skills"
SOURCE_SKILL="powersync"
# package:skills only installs skills whose directory name starts with the pub
# package name followed by a hyphen, so the skill is vendored under this name.
SKILL_NAME="powersync-sdk"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$ROOT/packages/powersync/skills"

check=false
tag=""
case "${1:-}" in
  --check) check=true ;;
  "") ;;
  *) tag="$1" ;;
esac

recorded_tag() {
  sed -n 's#^Source release: .*/releases/tag/\(v[^ )]*\).*#\1#p' "$SKILLS_DIR/README.md"
}

if $check; then
  tag="$(recorded_tag)"
  if [[ -z "$tag" ]]; then
    echo "Could not read the recorded release tag from $SKILLS_DIR/README.md" >&2
    exit 1
  fi
fi

auth=()
if [[ -n "${GH_TOKEN:-}" ]]; then
  auth=(-H "Authorization: Bearer $GH_TOKEN")
fi

if [[ -z "$tag" ]]; then
  tag="$(curl -fsSL ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$SOURCE_REPO/releases/latest" \
    | sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p')"
  if [[ -z "$tag" ]]; then
    echo "Could not determine the latest $SOURCE_REPO release" >&2
    exit 1
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

base="https://github.com/$SOURCE_REPO/releases/download/$tag"
echo "Fetching $SOURCE_SKILL skill from $SOURCE_REPO $tag"
curl -fsSL -o "$tmp/index.json" "$base/index.json"
curl -fsSL -o "$tmp/skill.tar.gz" "$base/$SOURCE_SKILL.tar.gz"

# index.json lists each skill with the sha256 digest of its archive.
expected="$(awk -v name="$SOURCE_SKILL" '
  $0 ~ "\"name\": *\"" name "\"" { found = 1 }
  found && /"digest"/ { print; exit }
' "$tmp/index.json" | sed -n 's/.*"sha256:\([0-9a-f]*\)".*/\1/p')"
if [[ -z "$expected" ]]; then
  echo "No digest for skill '$SOURCE_SKILL' in index.json" >&2
  exit 1
fi
if command -v sha256sum >/dev/null; then
  actual="$(sha256sum "$tmp/skill.tar.gz" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "$tmp/skill.tar.gz" | cut -d' ' -f1)"
fi
if [[ "$actual" != "$expected" ]]; then
  echo "Digest mismatch for $SOURCE_SKILL.tar.gz: expected $expected, got $actual" >&2
  exit 1
fi

out="$tmp/out"
mkdir -p "$out/$SKILL_NAME"
tar -xzf "$tmp/skill.tar.gz" -C "$out/$SKILL_NAME"

# Rename the skill in the SKILL.md frontmatter to match its directory name.
skill_md="$out/$SKILL_NAME/SKILL.md"
sed "1,/^---\$/ s/^name: $SOURCE_SKILL\$/name: $SKILL_NAME/" "$skill_md" > "$skill_md.tmp"
mv "$skill_md.tmp" "$skill_md"
if ! grep -qx "name: $SKILL_NAME" "$skill_md"; then
  echo "Failed to rename the skill in $skill_md" >&2
  exit 1
fi

cat > "$out/README.md" <<README
# PowerSync agent skill

This directory is vendored from [powersync-ja/agent-skills](https://github.com/$SOURCE_REPO)
and is installed into users' projects by [\`package:skills\`](https://pub.dev/packages/skills)
(\`dart run skills@ get\`). The upstream \`$SOURCE_SKILL\` skill is renamed to
\`$SKILL_NAME\` because \`package:skills\` only installs skills prefixed with the
package name.

Do not edit these files here. Contribute to the upstream repository instead, then
run \`tool/sync_skills.sh\` to pull the new release. CI also opens a PR when a
new release is available.

Source release: https://github.com/$SOURCE_REPO/releases/tag/$tag
Archive digest: sha256:$expected
README

if $check; then
  if diff -r "$out" "$SKILLS_DIR"; then
    echo "Vendored skill matches $SOURCE_REPO $tag"
  else
    echo "Vendored skill differs from $SOURCE_REPO $tag; run tool/sync_skills.sh $tag" >&2
    exit 1
  fi
else
  rm -rf "$SKILLS_DIR"
  mkdir -p "$SKILLS_DIR"
  cp -R "$out/." "$SKILLS_DIR/"
  echo "Vendored $SOURCE_REPO $tag into ${SKILLS_DIR#"$ROOT/"}"
fi

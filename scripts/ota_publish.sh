#!/bin/bash
# Publish a bacon OTA zip to GitHub Releases and update the Updater manifest.
#
# Computes sha256 (the entry "id") + size, reads ro.build.date.utc from the
# build, and either prints a one-entry manifest, merges the entry into an
# existing manifest (dedup by filename, newest first), or — with --github —
# uploads the zip as a release asset and commits the updated manifest.
#
# Usage:
#   ota_publish.sh --url-base https://example.com/zips [--zip PATH]
#   ota_publish.sh --url-base ... --merge ota/xdplus.json
#   ota_publish.sh --github --dry-run          # print what would be published
#   ota_publish.sh --github [--tag TAG] [--zip PATH] [--push]
#
# WARNING: --github without --dry-run UPLOADS. Creating a release and its asset
# is public and awkward to take back, so run --dry-run first, every time.
#
# The manifest the device fetches is the one named by lineage.updater.uri in
# device/gpd/xdplus/system.prop. Keep the two in step: publishing to a repo,
# branch or path that property does not name has no effect on any device.
#
# ⚠️ Released builds are `user`, not `userdebug`. This script refuses to
# publish anything else unless --allow-userdebug is given, because a debug
# build handed out as a release ships an open adbd and a console.
set -euo pipefail
source "$(dirname "$0")/env.sh"

GH_REPO_DEFAULT="Keyaku/gpd-xdplus-customrom"
GH_BRANCH_DEFAULT="main"
GH_MANIFEST_DEFAULT="ota/xdplus.json"

ZIP="" URLBASE="" MERGE="" DATETIME="" VERSION="18.1" ROMTYPE="unofficial"
GITHUB="" TAG="" PUSH="" ALLOW_USERDEBUG="" DRYRUN=""
GH_REPO="$GH_REPO_DEFAULT" GH_BRANCH="$GH_BRANCH_DEFAULT" GH_MANIFEST="$GH_MANIFEST_DEFAULT"
while [ $# -gt 0 ]; do
	case "$1" in
		--zip)         ZIP="$2"; shift 2;;
		--url-base)    URLBASE="${2%/}"; shift 2;;
		--merge)       MERGE="$2"; shift 2;;
		--datetime)    DATETIME="$2"; shift 2;;
		--version)     VERSION="$2"; shift 2;;
		--romtype)     ROMTYPE="$2"; shift 2;;
		--github)      GITHUB=1; shift;;
		--repo)        GH_REPO="$2"; shift 2;;
		--branch)      GH_BRANCH="$2"; shift 2;;
		--manifest)    GH_MANIFEST="$2"; shift 2;;
		--tag)         TAG="$2"; shift 2;;
		--push)        PUSH=1; shift;;
		--allow-userdebug) ALLOW_USERDEBUG=1; shift;;
		--dry-run)     DRYRUN=1; shift;;
		*) echo "unknown arg: $1" >&2; exit 2;;
	esac
done

[ -n "$ZIP" ] || ZIP="$XDZIP"   # env.sh: newest bacon zip by mtime
[ -f "$ZIP" ] || { echo "ERROR: zip not found: $ZIP" >&2; exit 2; }

FN="$(basename "$ZIP")"
SIZE="$(stat -c %s "$ZIP")"

# --- variant gate -----------------------------------------------------------
# The zip's own META-INF/com/android/metadata is authoritative: `post-build` is
# the target fingerprint, whose second-to-last field is the build variant. The
# staged out/ tree is not consulted — it describes whatever was built last,
# which is not necessarily this zip.
METADATA="$(unzip -p "$ZIP" META-INF/com/android/metadata 2>/dev/null || true)"
FINGERPRINT="$(printf '%s\n' "$METADATA" | sed -n 's/^post-build=//p' | head -1 || true)"
# …/<incremental>:<variant>/<keys> — take the field before the keys, then the
# part after its colon.
BUILD_TYPE="$(printf '%s\n' "$FINGERPRINT" | awk -F/ 'NF{print $(NF-1)}' | sed 's/.*://' || true)"
if [ -n "$GITHUB" ]; then
	if [ -z "$BUILD_TYPE" ]; then
		echo "ERROR: cannot determine ro.build.type for $FN — refusing to publish blind." >&2
		echo "       Rebuild with XDPLUS_RELEASE=1, or pass --allow-userdebug if you are certain." >&2
		[ -n "$ALLOW_USERDEBUG" ] || exit 4
	elif [ "$BUILD_TYPE" != "user" ] && [ -z "$ALLOW_USERDEBUG" ]; then
		echo "ERROR: $FN is a '$BUILD_TYPE' build; releases are 'user'." >&2
		echo "       Rebuild with XDPLUS_RELEASE=1 (build.sh), or pass --allow-userdebug." >&2
		exit 4
	fi
fi

SHA="$(sha256sum "$ZIP" | awk '{print $1}')"

# datetime: explicit > the zip's own post-timestamp > ro.build.date.utc from the
# staged out/ tree > filename YYYYMMDD (midnight UTC). post-timestamp comes from
# the zip itself and is the same value as ro.build.date.utc, so it is preferred:
# the bacon OTA is a block image and system/build.prop is not a plain zip entry.
# `|| true` on each probe so a miss (and any SIGPIPE from `head`) doesn't trip set -e.
if [ -z "$DATETIME" ]; then
	DATETIME="$(printf '%s\n' "$METADATA" | sed -n 's/^post-timestamp=//p' | head -1 || true)"
fi
if [ -z "$DATETIME" ] && [ -f "$XDOUT/system/build.prop" ]; then
	DATETIME="$(sed -n 's/^ro\.build\.date\.utc=//p' "$XDOUT/system/build.prop" | head -1 || true)"
fi
if [ -z "$DATETIME" ]; then
	D="$(echo "$FN" | grep -oE '[0-9]{8}' | head -1 || true)"
	[ -n "$D" ] && DATETIME="$(date -u -d "$D" +%s 2>/dev/null || true)"
fi
[ -n "$DATETIME" ] || { echo "ERROR: could not determine datetime; pass --datetime EPOCH" >&2; exit 3; }

# --- GitHub mode: derive the tag, the asset URL and the manifest to edit -----
REPO_DIR=""
if [ -n "$GITHUB" ]; then
	command -v gh >/dev/null || { echo "ERROR: --github needs the gh CLI" >&2; exit 2; }
	[ -n "$TAG" ] || TAG="$(date -u -d "@$DATETIME" +%Y%m%d)"
	URLBASE="https://github.com/$GH_REPO/releases/download/$TAG"
	# The manifest lives in this checkout — this script ships inside it. Resolve
	# through any symlink: the private scripts/ directory symlinks to this file,
	# and $0 there would put the manifest in the wrong tree entirely.
	REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
	MERGE="$REPO_DIR/$GH_MANIFEST"
	mkdir -p "$(dirname "$MERGE")"
fi

[ -n "$URLBASE" ] || { echo "ERROR: --url-base required (or use --github)" >&2; exit 2; }
URL="$URLBASE/$FN"

ENTRY_FN="$FN" ENTRY_SHA="$SHA" ENTRY_ROMTYPE="$ROMTYPE" ENTRY_SIZE="$SIZE" \
ENTRY_URL="$URL" ENTRY_VERSION="$VERSION" ENTRY_DT="$DATETIME" ENTRY_MERGE="$MERGE" \
python3 - <<'PY'
import json, os, sys

entry = {
	"datetime": int(os.environ["ENTRY_DT"]),
	"filename": os.environ["ENTRY_FN"],
	"id":       os.environ["ENTRY_SHA"],
	"romtype":  os.environ["ENTRY_ROMTYPE"],
	"size":     int(os.environ["ENTRY_SIZE"]),
	"url":      os.environ["ENTRY_URL"],
	"version":  os.environ["ENTRY_VERSION"],
}

merge = os.environ["ENTRY_MERGE"]
resp = []
if merge and os.path.exists(merge):
	with open(merge) as f:
		resp = json.load(f).get("response", [])
# dedup by filename, drop any prior entry with the same name, then prepend
resp = [e for e in resp if e.get("filename") != entry["filename"]]
resp.insert(0, entry)
resp.sort(key=lambda e: e.get("datetime", 0), reverse=True)

out = json.dumps({"response": resp}, indent=2)
if merge:
	with open(merge, "w") as f:
		f.write(out + "\n")
	sys.stderr.write(f"merged {entry['filename']} into {merge} ({len(resp)} entries)\n")
print(out)
PY

echo "---" >&2
echo "zip:      $ZIP" >&2
echo "variant:  ${BUILD_TYPE:-unknown}" >&2
echo "url:      $URL" >&2
echo "sha256:   $SHA" >&2
echo "datetime: $DATETIME" >&2

[ -n "$GITHUB" ] || exit 0

if [ -n "$DRYRUN" ]; then
	echo "--- DRY RUN: nothing uploaded, nothing committed ---" >&2
	echo "would create or reuse release $TAG on $GH_REPO, and upload $FN" >&2
	echo "would commit $GH_MANIFEST in $REPO_DIR${PUSH:+, then push it to $GH_BRANCH}" >&2
	git -C "$REPO_DIR" checkout -- "$GH_MANIFEST" 2>/dev/null || rm -f "$MERGE"
	exit 0
fi

# --- upload the payload, then land the manifest ------------------------------
# The release is created on first use and reused afterwards, so re-running with
# the same tag replaces the asset rather than failing.
echo "--- publishing to $GH_REPO release $TAG ---" >&2
if gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
	echo "release $TAG exists; uploading asset (clobbering any same-named one)" >&2
else
	gh release create "$TAG" --repo "$GH_REPO" \
		--title "LineageOS 18.1 for the GPD XD+ — $TAG" \
		--notes "Unofficial LineageOS 18.1 build for the GPD XD+ (\`xdplus\`), \`user\` variant.

Install per [docs/INSTALL.md](https://github.com/$GH_REPO/blob/$GH_BRANCH/docs/INSTALL.md). The zip writes \`boot\` as well as \`system\`, so re-apply Magisk afterwards if you are rooted.

\`\`\`
sha256  $SHA
size    $SIZE bytes
\`\`\`" >&2
fi
gh release upload "$TAG" "$ZIP" --repo "$GH_REPO" --clobber >&2

git -C "$REPO_DIR" add "$GH_MANIFEST"
if git -C "$REPO_DIR" diff --cached --quiet -- "$GH_MANIFEST"; then
	echo "manifest unchanged; nothing to commit" >&2
else
	git -C "$REPO_DIR" commit -q -m "OTA: publish $FN" -- "$GH_MANIFEST"
	echo "committed the manifest update" >&2
fi

if [ -n "$PUSH" ]; then
	git -C "$REPO_DIR" push origin "HEAD:$GH_BRANCH" >&2
	echo "pushed. The device fetches:" >&2
	echo "  https://raw.githubusercontent.com/$GH_REPO/$GH_BRANCH/$GH_MANIFEST" >&2
	echo "raw.githubusercontent.com caches for ~5 min — a stale fetch is not a wrong URI." >&2
else
	echo "NOT pushed (pass --push). The manifest is committed locally only, so no" >&2
	echo "device can see this release yet." >&2
fi

#!/bin/zsh
# Bump the app version, verify the build, commit, tag, and optionally push.
#
#   ./scripts/release/release.sh            # prompt for version
#   ./scripts/release/release.sh 0.2.0      # explicit version
#   ./scripts/release/release.sh --push     # also push branch and tag
#
# The release commit stages every current working-tree change. Commit or stash
# unrelated edits first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLIST="$ROOT_DIR/Resources/Info.plist"

VERSION=""
PUSH=0
VERIFY=1
BRANCH=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--push) PUSH=1 ;;
	--no-verify) VERIFY=0 ;;
	--branch) BRANCH="${2:-}"; shift ;;
	-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
	-*) echo "unknown option: $1" >&2; exit 2 ;;
	*) VERSION="$1" ;;
	esac
	shift
done

cd "$ROOT_DIR"

current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [[ -z "$VERSION" ]]; then
	read -r major minor patch <<< "${current_version//./ }"
	suggested_version="$major.$minor.$((patch + 1))"
	if [[ ! -t 0 ]]; then
		echo "error: 非交互运行必须显式传入版本号，例如 $0 0.1.0 --push" >&2
		exit 2
	fi
	echo "当前版本：$current_version"
	printf '请输入发布版本号 [%s]（输入 q 取消）：' "$suggested_version"
	read -r VERSION
	[[ "$VERSION" == "q" ]] && exit 0
	VERSION="${VERSION:-$suggested_version}"
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "error: version must look like 1.2.3, got '$VERSION'" >&2
	exit 2
fi

if [[ -z "$BRANCH" ]]; then
	BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi
if [[ "$BRANCH" == "HEAD" ]]; then
	echo "error: detached HEAD; check out the release branch first" >&2
	exit 1
fi

if [[ -t 0 ]]; then
	echo "发布版本：$current_version -> $VERSION；分支：$BRANCH"
	echo "将运行测试和构建、暂存全部当前改动、创建提交与标签。"
	if [[ $PUSH -eq 1 ]]; then
		echo "随后推送到 GitHub，触发 Release 和已启用的 Gitee 同步。"
	fi
	printf '确认继续？[y/N]：'
	read -r confirmation
	if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
		echo "已取消发布。"
		exit 0
	fi
fi

tag="v$VERSION"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
	echo "error: tag $tag already exists locally" >&2
	exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
	echo "error: tag $tag already exists on origin" >&2
	exit 1
fi

if [[ $VERIFY -eq 1 ]]; then
	echo "Verifying tags and tests before release..."
	./Tests/run.sh
	./build.sh >/dev/null
fi

read -r major minor patch <<< "${VERSION//./ }"
build_number=$((major * 10000 + minor * 100 + patch))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$PLIST"
plutil -lint "$PLIST" >/dev/null

echo "Version: $current_version -> $VERSION (build $build_number)"

git add -A
if ! git diff --cached --quiet; then
	git commit -m "release: $tag"
fi
git tag -a "$tag" -m "$tag"

if [[ $PUSH -eq 1 ]]; then
	git push origin "$BRANCH"
	git push origin "$tag"
	echo "Pushed $BRANCH and $tag; GitHub Actions will publish the release."
else
	echo "Created commit and tag $tag. Push with:"
	echo "  git push origin $BRANCH && git push origin $tag"
fi

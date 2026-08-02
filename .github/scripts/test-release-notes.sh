#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(git -C "$script_dir" rev-parse --show-toplevel)
notes_file=$(mktemp)
stderr_file=$(mktemp)
trap 'rm -f "$notes_file" "$stderr_file"' EXIT

cd "$repo_root"

assert_build_relevant() {
    local hash=$1

    if ! .github/scripts/build-relevance.sh commit "$hash"; then
        printf 'expected %s to affect the build\n' "$hash" >&2
        exit 1
    fi
}

assert_not_build_relevant() {
    local hash=$1

    if .github/scripts/build-relevance.sh commit "$hash"; then
        printf 'expected %s not to affect the build\n' "$hash" >&2
        exit 1
    fi
}

assert_contains() {
    local expected=$1

    if ! grep -Fq -- "$expected" "$notes_file"; then
        printf 'release notes missing expected text: %s\n' "$expected" >&2
        sed -n '1,240p' "$notes_file" >&2
        exit 1
    fi
}

# Sources/<Domain> 是 DYYY 的真实构建输入；发布脚本自身不应触发业务 Release。
assert_build_relevant 2419be8
assert_build_relevant 7b0befb
assert_not_build_relevant f12c157

RELEASE_PREVIOUS_TAG='DYYY_2.3-0#18' \
RELEASE_HEAD_SHA=7b0befb \
RELEASE_TITLE='DYYY_2.3-0#19' \
GITHUB_REPOSITORY='VexCove/DYYY' \
    .github/scripts/generate-release-notes.sh "$notes_file" 2>"$stderr_file" >/dev/null

assert_contains '### 新功能与体验改进'
assert_contains '综合搜索 AI 浮钮隐藏支持'
assert_contains '2419be88'
assert_contains '开启“隐藏键盘 AI”后，综合搜索结果页右下角的“继续追问”等 AI 浮钮也会一并隐藏，并避免入口先出现再消失。'
assert_contains '### Bug 修复'
assert_contains '图文播放倍率状态'
assert_contains '7b0befb7'
assert_contains '修复图文场景可能沿用上一个视频倍率状态的问题；切换倍率或恢复 1.0 倍速时，现在会正确作用于当前图文内容，并避免误触发长按快进转场。'

if grep -Eq 'Release note fallback|^warning:' "$stderr_file"; then
    printf 'evidence-backed #19 notes unexpectedly used the generic fallback\n' >&2
    cat "$stderr_file" >&2
    exit 1
fi

# 没有显式正文且没有专用差异证据时，用户可见的 feat/fix/perf 仍需得到
# 一句可读说明，同时在 CI 中提示维护者补充更精确的 Release-Note。
generic_parent=$(git rev-parse 'ff80c90^')
RELEASE_PREVIOUS_TAG="$generic_parent" \
RELEASE_HEAD_SHA=ff80c90 \
RELEASE_TITLE='fallback-test' \
GITHUB_REPOSITORY='VexCove/DYYY' \
GITHUB_ACTIONS=true \
    .github/scripts/generate-release-notes.sh "$notes_file" 2>"$stderr_file" >/dev/null

assert_contains '主页关注确认弹窗与提示优化'
assert_contains '现在可以使用主页关注确认弹窗与提示优化。'
if ! grep -Fq '::warning title=Release note fallback::' "$stderr_file"; then
    printf 'generic release-note fallback did not emit a GitHub Actions warning\n' >&2
    cat "$stderr_file" >&2
    exit 1
fi

printf 'release-note regression tests passed\n'

#!/usr/bin/env bash
#
# sync-android.sh —— 一键同步上游 certimate 并发布安卓版
#
# 流程：
#   1. 拉取 upstream (certimate-go/certimate) 与 origin 最新代码/标签
#   2. 若上游有新提交，合并进本地 main 并推送到 origin
#      （触发 CI 构建 linux/arm64 + android/arm64 两个 Artifact）
#   3. 基于上游最新版本号打 tag（如 v0.4.36 -> v0.4.36-android）并推送
#      （触发 CI 把两个二进制上传到 GitHub Release，永久可下载）
#
# 用法：
#   ./sync-android.sh
#
# 可选环境变量：
#   UPSTREAM    上游远程名，默认 upstream
#   ORIGIN      自己的 fork 远程名，默认 origin
#   TAG_SUFFIX  版本后缀，默认 -android
#
set -euo pipefail

UPSTREAM="${UPSTREAM:-upstream}"
ORIGIN="${ORIGIN:-origin}"
TAG_SUFFIX="${TAG_SUFFIX:--android}"

echo "==> [1/5] 配置 HTTP/1.1 以规避部分网络下的 HTTP/2 问题"
git config http.version HTTP/1.1 2>/dev/null || true

echo "==> [2/5] 拉取上游与 origin 最新引用（含标签）"
git fetch "$UPSTREAM" --tags
git fetch "$ORIGIN" --tags

# 切到 main 并确保工作区干净
git switch main 2>/dev/null || git checkout main
if [ -n "$(git status --porcelain)" ]; then
  echo "错误：工作区存在未提交改动，请先 commit 或 stash 后再运行。" >&2
  exit 1
fi

# 计算上游领先提交数
UP_AHEAD=$(git rev-list --count "$ORIGIN/main..$UPSTREAM/main" 2>/dev/null || echo 0)
if [ "$UP_AHEAD" -gt 0 ]; then
  echo "==> [3/5] 上游有 $UP_AHEAD 个新提交，合并并推送 main"
  git merge "$UPSTREAM/main" --no-edit
  for i in 1 2 3 4 5; do
    if git push "$ORIGIN" main; then break; fi
    echo "    push 失败，${i} 后重试..."; sleep 3
  done
else
  echo "==> [3/5] 上游无新提交，跳过合并"
fi

# 取上游最新 tag（作为版本基准）
UP_TAG=$(git describe --tags --abbrev=0 "$UPSTREAM/main" 2>/dev/null || true)
if [ -z "$UP_TAG" ]; then
  echo "错误：无法获取上游最新 tag，请检查 upstream 远程是否正确配置。" >&2
  exit 1
fi
NEW_TAG="${UP_TAG}${TAG_SUFFIX}"

if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
  echo "==> [4/5] tag $NEW_TAG 已存在，跳过打 tag（如需重新发布请先删除该 tag）。"
  exit 0
fi

echo "==> [4/5] 基于上游 $UP_TAG 打 tag: $NEW_TAG"
git tag -a "$NEW_TAG" -m "Certimate 安卓 ARM64 构建 (基于 $UP_TAG + Android 启动脚本/CI)"
for i in 1 2 3 4 5; do
  if git push "$ORIGIN" "$NEW_TAG"; then break; fi
  echo "    push tag 失败，${i} 后重试..."; sleep 3
done

REPO=$(git remote get-url "$ORIGIN" | sed -E 's#.*github.com[:/]##; s#\.git$##')
echo "==> [5/5] 完成。CI 正在构建并发布："
echo "    https://github.com/$REPO/releases/tag/$NEW_TAG"

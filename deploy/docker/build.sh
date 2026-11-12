#!/usr/bin/env bash
set -e

# dash 不支持 read -s（密码不回显），用 sh build.sh 调用时切回 bash
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# 项目根目录（deploy/docker 的上两级），作为构建上下文
ROOT=$(cd "$(dirname "$0")/../.." && pwd)

# 镜像名固定取项目名（仓库根目录名），可用 PROJECT_NAME 环境变量覆盖
PROJECT_NAME=${PROJECT_NAME:-$(basename "$ROOT")}

DOCKERFILE_FULL="$ROOT/deploy/docker/Dockerfile"
DOCKERFILE_BASE="$ROOT/deploy/docker/Dockerfile-base"

# 是否交互：从终端运行时才提问，非交互（CI 等）走环境变量
INTERACTIVE=0
if [ -t 0 ]; then
  INTERACTIVE=1
fi

# 1. 镜像仓库地址：REGISTRY 显式设置时不询问
if [ -z "$REGISTRY" ]; then
  if [ "$INTERACTIVE" = "1" ]; then
    while [ -z "$REGISTRY" ]; do
      printf '镜像仓库地址（如 registry.cn-hangzhou.aliyuncs.com/namespace）: '
      read -r answer || answer=""
      REGISTRY=$(printf '%s' "$answer" | sed 's|[[:space:]]*$||')
      [ -z "$REGISTRY" ] && echo "仓库地址不能为空，请重新输入"
    done
  else
    echo "错误：非交互模式下必须通过环境变量 REGISTRY 指定镜像仓库地址" >&2
    exit 1
  fi
fi
# 去掉仓库地址结尾的斜杠，避免拼出双斜杠
while [ "${REGISTRY%/}" != "$REGISTRY" ]; do
  REGISTRY=${REGISTRY%/}
done
if [ -z "$REGISTRY" ]; then
  echo "错误：镜像仓库地址不能为空" >&2
  exit 1
fi

echo "镜像名：${PROJECT_NAME}（取自项目目录名）"

# 2. 版本号：TAG 显式设置时不询问；交互下询问，非交互默认 latest
if [ -z "$TAG" ]; then
  if [ "$INTERACTIVE" = "1" ]; then
    printf '版本号 [latest]: '
    read -r answer || answer=""
    TAG=$(printf '%s' "$answer" | sed 's|[[:space:]]||g')
    TAG=${TAG:-latest}
  else
    TAG=latest
  fi
fi

IMAGE="$REGISTRY/$PROJECT_NAME:$TAG"

# 3. 构建哪种镜像：BASE_ONLY 显式设置（1=仅基础镜像，0=完整镜像）时不询问
if [ -z "${BASE_ONLY+x}" ]; then
  if [ "$INTERACTIVE" = "1" ]; then
    echo "构建哪种镜像？"
    echo "  1) 完整镜像（含项目代码）"
    echo "  2) 基础镜像（仅依赖，不含代码）"
    printf '请选择 [1]: '
    read -r answer || answer=""
    case "$answer" in
      2|基础|base|BASE) BASE_ONLY=1 ;;
      *) BASE_ONLY=0 ;;
    esac
  else
    BASE_ONLY=0
  fi
fi

if [ "$BASE_ONLY" = "1" ]; then
  DOCKERFILE="$DOCKERFILE_BASE"
  echo "镜像内容：基础镜像（不含代码）"
else
  DOCKERFILE="$DOCKERFILE_FULL"
  echo "镜像内容：完整镜像（含代码）"
fi

echo "目标镜像：$IMAGE"

# local.ini 仍从镜像排除；完整镜像会带上 dev.ini（含凭据），仓库必须私有
docker build -f "$DOCKERFILE" -t "$IMAGE" "$ROOT"

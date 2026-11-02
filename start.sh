#!/bin/bash
# xiaomusic 裸机直跑一键启动（macOS 优先，兼容 Linux）
# 首次运行自动完成：建 venv → 装 xiaomusic（PyPI 失败自动换清华镜像）
# → 生成 config.json（已预修全部已知坑，见 README）
set -e
cd "$(dirname "$0")"

# 坑④：下载功能以裸命令名启动 yt-dlp，venv/bin 必须在 PATH 里
export PATH="$(pwd)/.venv/bin:$PATH"

# ---- 1) 虚拟环境与依赖 ----
if [ ! -x .venv/bin/xiaomusic ]; then
  echo "首次运行：创建虚拟环境并安装 xiaomusic ..."
  if command -v uv >/dev/null 2>&1; then
    uv venv --python 3.12
    export UV_HTTP_TIMEOUT=20   # 直连 PyPI 超时快速失败，立即切镜像，避免国内网络干等
    uv pip install --python .venv/bin/python xiaomusic \
      || uv pip install --python .venv/bin/python --index-url https://pypi.tuna.tsinghua.edu.cn/simple xiaomusic
  else
    python3 -m venv .venv
    .venv/bin/pip install --timeout 20 xiaomusic \
      || .venv/bin/pip install --timeout 60 -i https://pypi.tuna.tsinghua.edu.cn/simple xiaomusic
  fi
fi

# ---- 2) 生成 config.json（已存在则不动，你的网页设置保存在 conf/setting.json）----
if [ ! -f config.json ]; then
  echo "生成 config.json ..."
  .venv/bin/xiaomusic --enable_config_example >/dev/null 2>&1 || true
  IP=$(ipconfig getifaddr en0 2>/dev/null || (hostname -I 2>/dev/null | awk '{print $1}') || true)
  FFMPEG_DIR=$(dirname "$(command -v ffmpeg)" 2>/dev/null || true)
  python3 - "$IP" "$FFMPEG_DIR" << 'PYEOF'
import json, sys
ip, ffmpeg_dir = sys.argv[1].strip(), sys.argv[2].strip()
c = json.load(open("config-example.json"))
c["enable_pull_ask"] = True       # 坑①：不开永远截不到语音口令，音箱只会播小米默认内容
c["public_port"] = c["port"]      # 坑②：默认58090是Docker端口映射用的，裸跑必须等于真实端口，否则音箱拉流失败
c["hostname"] = f"http://{ip}"    # 音箱从这里拉流；路由器重新分配IP后需在网页设置里改
if ffmpeg_dir:
    c["ffmpeg_location"] = ffmpeg_dir  # 坑③：默认./ffmpeg/bin不存在，下载歌曲转码必需
c["music_path"] = "music"
c["enable_analytics"] = False
c["enable_config_example"] = False
json.dump(c, open("config.json", "w"), ensure_ascii=False, indent=2)
print(f"  hostname = http://{ip}")
if ffmpeg_dir:
    print(f"  ffmpeg   = {ffmpeg_dir}")
else:
    print("  ⚠️ 未找到 ffmpeg，下载歌曲功能不可用（brew install ffmpeg）")
PYEOF
  rm -f config-example.json
fi

mkdir -p music

# ---- 3) 启动 ----
PORT=$(python3 -c "import json;print(json.load(open('config.json'))['port'])" 2>/dev/null || echo 8090)
if [ -f run.pid ] && kill -0 "$(cat run.pid)" 2>/dev/null; then
  echo "已在运行 (PID $(cat run.pid))，管理页: http://localhost:$PORT"
  exit 0
fi
.venv/bin/xiaomusic --config config.json >> run.log 2>&1 &
echo $! > run.pid
echo "xiaomusic 已启动 (PID $!)"
echo "管理页: http://localhost:$PORT —— 首次使用先在设置页填小米账号密码并选择音箱"
echo "提醒：电脑休眠/合盖服务就断，播放时保持唤醒；停止服务: kill \$(cat run.pid)"

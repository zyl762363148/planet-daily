#!/bin/sh
# 独立语音环境；不向系统 Python 安装依赖，也不要求 API key。
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
venv_path="$project_root/.venv-tts"
bootstrap_python="${TTS_BOOTSTRAP_PYTHON:-/usr/bin/python3}"

if [ ! -x "$venv_path/bin/python" ]; then
    "$bootstrap_python" -m venv "$venv_path"
fi
"$venv_path/bin/python" -m pip install --requirement "$project_root/requirements-tts.txt"
"$venv_path/bin/python" -c 'import edge_tts; print("在线自然语音环境已就绪：edge-tts " + edge_tts.__version__)'
printf '%s\n' '在 config.json 的 tts 中设置 engine=edge、voice=zh-CN-YunyangNeural、natural_rate=+0%。'

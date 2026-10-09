#!/bin/zsh
# Создаёт локальное Python-окружение для сборщика.
set -e
cd "$(dirname "$0")/.."
python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r collector/requirements.txt
echo "venv готов: $(pwd)/.venv"

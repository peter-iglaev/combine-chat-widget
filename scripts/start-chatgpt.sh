#!/bin/zsh
# Запускает ChatGPT.app с отладочным портом 127.0.0.1:9333.
# Если ChatGPT уже открыт без порта, он будет закрыт и открыт заново.
cd "$(dirname "$0")/.."
exec .venv/bin/python -I collector/chatbar.py launch-gpt

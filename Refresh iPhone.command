#!/bin/zsh
set -eu
cd "$(dirname "$0")"
python3 scripts/install_phone.py
printf '\nPress Return to close.\n'
read -r

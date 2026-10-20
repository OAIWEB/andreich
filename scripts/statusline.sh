#!/bin/bash
# Статусная строка Claude Code: модель, папка и лимиты подписки.
# Цифры берёт из кэша Андреича (scripts/usage.py), в сеть не ходит — обновление идёт фоном.
input=$(cat)
model=$(printf '%s' "$input" | /usr/bin/python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("model",{}).get("display_name",""))' 2>/dev/null)
dir=$(printf '%s' "$input" | /usr/bin/python3 -c 'import json,os,sys;d=json.load(sys.stdin);print(os.path.basename(d.get("workspace",{}).get("current_dir","")))' 2>/dev/null)
limits=$(/usr/bin/python3 "$HOME/Проекты/Андреич-чёлка/scripts/usage.py" --line --bg 2>/dev/null)
printf '%s' "${model:+$model · }${dir:+$dir · }${limits}"

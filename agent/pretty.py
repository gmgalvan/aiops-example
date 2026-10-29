"""Muestra en vivo lo que hace Claude Code (stream-json): herramientas usadas y respuesta."""

import json
import os
import re
import sys

DIM, BOLD, CYAN, RESET = "\033[2m", "\033[1m", "\033[36m", "\033[0m"
# Herramientas internas de Claude Code que no aportan a la demo.
HIDDEN = {"ToolSearch", "TodoWrite"}

for line in sys.stdin:
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get("type") == "assistant":
        for block in event["message"].get("content", []):
            if block.get("type") == "tool_use":
                if block["name"] in HIDDEN:
                    continue
                args = block.get("input", {})
                path = args.get("file_path") or args.get("path")
                shown = args.get("command") or (path and os.path.relpath(path)) or json.dumps(args, ensure_ascii=False)
                print(f"{CYAN}▶ {block['name']}{RESET} {DIM}{shown[:160]}{RESET}", flush=True)
            elif block.get("type") == "text" and block["text"].strip():
                # La propuesta de PR (bloque json) la muestra remediate.sh ya formateada.
                text = re.sub(r"```json\s*\{.*?\}\s*```", f"{DIM}(propuesta de PR: ver el paso 3){RESET}",
                              block["text"], flags=re.S)
                print(f"\n{text}\n", flush=True)
    elif event.get("type") == "result":
        turns, secs = event.get("num_turns"), event.get("duration_ms", 0) / 1000
        print(f"{DIM}── {turns} pasos · {secs:.0f} s{RESET}", flush=True)

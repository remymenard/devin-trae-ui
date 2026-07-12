#!/usr/bin/env bash
# devin-trae-ui installer — Linux & macOS
# Injects trae-look.css into a VS Code-family editor (Devin/Windsurf,
# VS Code, Cursor, Antigravity), optionally patches tab height to 40px
# (Trae's), and re-computes product.json checksums so the editor does
# not complain about a "corrupt" installation.
#
# Usage:
#   ./install.sh                      # auto-detect installed editors
#   ./install.sh --app cursor         # target a specific editor
#   ./install.sh --path /path/to/resources/app
#   ./install.sh --no-tab-height      # skip the 35->40px tab patch
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS_SRC="$SCRIPT_DIR/trae-look.css"
START='/*======TRAE-LOOK-START======*/'
END='/*======TRAE-LOOK-END======*/'

APP_FILTER=""
APP_PATH=""
TAB_PATCH=1
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --app)  APP_FILTER="$2"; shift 2 ;;
    --path) APP_PATH="$2"; shift 2 ;;
    --no-tab-height) TAB_PATCH=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

[ -f "$CSS_SRC" ] || { echo "trae-look.css not found next to installer" >&2; exit 1; }

# ---------- editor detection ----------
# each candidate: "<name>|<resources/app path>"
candidates() {
  local os; os="$(uname -s)"
  if [ "$os" = "Darwin" ]; then
    local -a apps=(
      "devin|/Applications/Devin.app/Contents/Resources/app"
      "windsurf|/Applications/Windsurf.app/Contents/Resources/app"
      "vscode|/Applications/Visual Studio Code.app/Contents/Resources/app"
      "cursor|/Applications/Cursor.app/Contents/Resources/app"
      "antigravity|/Applications/Antigravity.app/Contents/Resources/app"
    )
    printf '%s\n' "${apps[@]}"
  else
    local -a apps=(
      "devin|$HOME/.local/opt/Devin/resources/app"
      "devin|/opt/Devin/resources/app"
      "windsurf|/usr/share/windsurf/resources/app"
      "windsurf|/opt/windsurf/resources/app"
      "vscode|/usr/share/code/resources/app"
      "vscode|/opt/visual-studio-code/resources/app"
      "cursor|/usr/share/cursor/resources/app"
      "cursor|/opt/cursor/resources/app"
      "antigravity|/usr/share/antigravity/resources/app"
      "antigravity|/opt/antigravity/resources/app"
    )
    printf '%s\n' "${apps[@]}"
  fi
}

resolve_target() {
  if [ -n "$APP_PATH" ]; then
    echo "custom|$APP_PATH"
    return
  fi
  local found=()
  while IFS= read -r line; do
    local name="${line%%|*}" path="${line#*|}"
    [ -n "$APP_FILTER" ] && [ "$name" != "$APP_FILTER" ] && continue
    [ -f "$path/out/vs/workbench/workbench.desktop.main.css" ] && found+=("$line")
  done < <(candidates)
  if [ ${#found[@]} -eq 0 ]; then
    echo "no editor found${APP_FILTER:+ for --app $APP_FILTER}. Use --path <resources/app>." >&2
    exit 1
  fi
  if [ ${#found[@]} -eq 1 ]; then
    echo "${found[0]}"
    return
  fi
  echo "Multiple editors found:" >&2
  local i=1
  for f in "${found[@]}"; do echo "  $i) ${f%%|*}  (${f#*|})" >&2; i=$((i+1)); done
  printf "Pick one [1-%d]: " ${#found[@]} >&2
  read -r pick
  echo "${found[$((pick-1))]}"
}

TARGET="$(resolve_target)"
NAME="${TARGET%%|*}"
APP="${TARGET#*|}"
CSS="$APP/out/vs/workbench/workbench.desktop.main.css"
JSF="$APP/out/vs/workbench/workbench.desktop.main.js"
PRODUCT="$APP/product.json"

[ -f "$CSS" ] || { echo "workbench css not found at $CSS" >&2; exit 1; }
if [ ! -w "$CSS" ]; then
  echo "No write access to $APP — re-run with sudo." >&2
  exit 1
fi

echo "Target: $NAME ($APP)"

# ---------- python3/node helper for JSON + regex work ----------
run_py() {
  if command -v python3 >/dev/null 2>&1; then python3 "$@"; else
    echo "python3 is required (used for safe CSS/JSON editing)" >&2; exit 1
  fi
}

if [ "$UNINSTALL" -eq 1 ]; then
  if [ -f "$CSS.orig" ]; then
    cp "$CSS.orig" "$CSS"
    echo "Restored original workbench CSS."
  else
    # strip our block if no backup
    run_py - "$CSS" <<'PY'
import sys, re
p = sys.argv[1]
txt = open(p, encoding="utf-8", errors="ignore").read()
txt = re.sub(r"/\*=+TRAE-LOOK-START=+\*/.*?/\*=+TRAE-LOOK-END=+\*/\n?", "", txt, flags=re.S)
open(p, "w", encoding="utf-8").write(txt)
PY
    echo "Removed TRAE-LOOK block."
  fi
  if [ -f "$JSF" ] && grep -q 'EDITOR_TAB_HEIGHT={normal:40' "$JSF"; then
    run_py - "$JSF" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", errors="ignore").read()
open(p, "w", encoding="utf-8").write(s.replace("EDITOR_TAB_HEIGHT={normal:40", "EDITOR_TAB_HEIGHT={normal:35"))
PY
    echo "Reverted tab height 40->35."
  fi
else
  # ---------- 1. backup once ----------
  [ -f "$CSS.orig" ] || cp "$CSS" "$CSS.orig"

  # ---------- 2. inject CSS between sentinels (idempotent) ----------
  run_py - "$CSS" "$CSS_SRC" <<'PY'
import sys, re
css_path, src_path = sys.argv[1], sys.argv[2]
txt = open(css_path, encoding="utf-8", errors="ignore").read()
txt = re.sub(r"/\*=+TRAE-LOOK-START=+\*/.*?/\*=+TRAE-LOOK-END=+\*/", "", txt, flags=re.S).rstrip()
block = open(src_path, encoding="utf-8").read().strip()
open(css_path, "w", encoding="utf-8").write(
    txt + "\n/*======TRAE-LOOK-START======*/\n" + block + "\n/*======TRAE-LOOK-END======*/\n")
PY
  echo "CSS injected."

  # ---------- 3. tab height 35 -> 40 (Trae) ----------
  if [ "$TAB_PATCH" -eq 1 ] && [ -f "$JSF" ] && grep -q 'EDITOR_TAB_HEIGHT={normal:35' "$JSF"; then
    run_py - "$JSF" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", errors="ignore").read()
open(p, "w", encoding="utf-8").write(s.replace("EDITOR_TAB_HEIGHT={normal:35", "EDITOR_TAB_HEIGHT={normal:40"))
PY
    echo "Tab height patched 35->40."
  fi
fi

# ---------- 4. fix product.json checksums (both install & uninstall) ----------
run_py - "$PRODUCT" "$APP" <<'PY'
import sys, json, hashlib, base64, os
product_path, app_root = sys.argv[1], sys.argv[2]
try:
    p = json.load(open(product_path, encoding="utf-8"))
except Exception:
    sys.exit(0)
sums = p.get("checksums")
if not isinstance(sums, dict):
    sys.exit(0)
changed = 0
for rel in list(sums.keys()):
    f = os.path.join(app_root, "out", rel)
    if os.path.isfile(f):
        h = hashlib.sha256(open(f, "rb").read()).digest()
        new = base64.b64encode(h).decode().rstrip("=")
        if sums[rel] != new:
            sums[rel] = new; changed += 1
if changed:
    json.dump(p, open(product_path, "w"), indent="\t")
    print(f"Fixed {changed} checksum(s).")
PY

echo "Done. Restart $NAME to see the changes."
echo "Note: editor updates overwrite these files — just re-run this installer."

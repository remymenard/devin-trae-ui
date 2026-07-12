#!/usr/bin/env bash
# devin-trae-ui uninstaller — restores the original workbench CSS,
# reverts the tab-height patch and re-fixes checksums.
# Same flags as install.sh (--app, --path).
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh" --uninstall "$@"

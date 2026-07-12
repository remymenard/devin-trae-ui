# devin-trae-ui uninstaller — restores the original workbench CSS,
# reverts the tab-height patch and re-fixes checksums.
# Same flags as install.ps1 (-App, -Path).
param([string]$App = "", [string]$Path = "")
& (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "install.ps1") -App $App -Path $Path -Uninstall

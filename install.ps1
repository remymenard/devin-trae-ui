# devin-trae-ui installer — Windows (PowerShell 5.1+)
# Injects trae-look.css into a VS Code-family editor (Devin/Windsurf,
# VS Code, Cursor, Antigravity), optionally patches tab height to 40px
# (Trae's), and re-computes product.json checksums so the editor does
# not complain about a "corrupt" installation.
#
# Usage (from the repo folder):
#   .\install.ps1                    # auto-detect installed editors
#   .\install.ps1 -App cursor        # target a specific editor
#   .\install.ps1 -Path "C:\...\resources\app"
#   .\install.ps1 -NoTabHeight       # skip the 35->40px tab patch
#   .\install.ps1 -Uninstall         # restore original files
param(
  [string]$App = "",
  [string]$Path = "",
  [switch]$NoTabHeight,
  [switch]$Uninstall
)
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CssSrc = Join-Path $ScriptDir "trae-look.css"
if (-not (Test-Path $CssSrc)) { throw "trae-look.css not found next to installer" }

$StartMark = "/*======TRAE-LOOK-START======*/"
$EndMark   = "/*======TRAE-LOOK-END======*/"

# ---------- editor detection ----------
$LocalPrograms = Join-Path $env:LOCALAPPDATA "Programs"
$Candidates = @(
  @{ Name = "devin";       Path = Join-Path $LocalPrograms "Devin\resources\app" },
  @{ Name = "windsurf";    Path = Join-Path $LocalPrograms "Windsurf\resources\app" },
  @{ Name = "vscode";      Path = Join-Path $LocalPrograms "Microsoft VS Code\resources\app" },
  @{ Name = "cursor";      Path = Join-Path $LocalPrograms "cursor\resources\app" },
  @{ Name = "antigravity"; Path = Join-Path $LocalPrograms "Antigravity\resources\app" }
)

if ($Path) {
  $Target = @{ Name = "custom"; Path = $Path }
} else {
  $Found = @($Candidates | Where-Object {
    ($App -eq "" -or $_.Name -eq $App) -and
    (Test-Path (Join-Path $_.Path "out\vs\workbench\workbench.desktop.main.css"))
  })
  if ($Found.Count -eq 0) { throw "No editor found. Use -Path <resources\app>." }
  if ($Found.Count -eq 1) { $Target = $Found[0] }
  else {
    Write-Host "Multiple editors found:"
    for ($i = 0; $i -lt $Found.Count; $i++) { Write-Host "  $($i+1)) $($Found[$i].Name)  ($($Found[$i].Path))" }
    $Pick = [int](Read-Host "Pick one [1-$($Found.Count)]")
    $Target = $Found[$Pick - 1]
  }
}

$AppRoot = $Target.Path
$Css  = Join-Path $AppRoot "out\vs\workbench\workbench.desktop.main.css"
$Js   = Join-Path $AppRoot "out\vs\workbench\workbench.desktop.main.js"
$Prod = Join-Path $AppRoot "product.json"
if (-not (Test-Path $Css)) { throw "workbench css not found at $Css" }
Write-Host "Target: $($Target.Name) ($AppRoot)"

function Strip-Block([string]$Text) {
  $pattern = [regex]::Escape($StartMark) + "[\s\S]*?" + [regex]::Escape($EndMark) + "\r?\n?"
  return [regex]::Replace($Text, $pattern, "")
}

if ($Uninstall) {
  if (Test-Path "$Css.orig") {
    Copy-Item "$Css.orig" $Css -Force
    Write-Host "Restored original workbench CSS."
  } else {
    $txt = Get-Content $Css -Raw
    Set-Content -Path $Css -Value (Strip-Block $txt) -NoNewline -Encoding UTF8
    Write-Host "Removed TRAE-LOOK block."
  }
  if ((Test-Path $Js) -and (Select-String -Path $Js -Pattern "EDITOR_TAB_HEIGHT=\{normal:40" -Quiet)) {
    $js = Get-Content $Js -Raw
    Set-Content -Path $Js -Value ($js.Replace("EDITOR_TAB_HEIGHT={normal:40", "EDITOR_TAB_HEIGHT={normal:35")) -NoNewline -Encoding UTF8
    Write-Host "Reverted tab height 40->35."
  }
} else {
  # ---------- 1. backup once ----------
  if (-not (Test-Path "$Css.orig")) { Copy-Item $Css "$Css.orig" }

  # ---------- 2. inject CSS between sentinels (idempotent) ----------
  $txt = (Strip-Block (Get-Content $Css -Raw)).TrimEnd()
  $block = (Get-Content $CssSrc -Raw).Trim()
  Set-Content -Path $Css -Value ($txt + "`n$StartMark`n" + $block + "`n$EndMark`n") -NoNewline -Encoding UTF8
  Write-Host "CSS injected."

  # ---------- 3. tab height 35 -> 40 (Trae) ----------
  if (-not $NoTabHeight -and (Test-Path $Js) -and (Select-String -Path $Js -Pattern "EDITOR_TAB_HEIGHT=\{normal:35" -Quiet)) {
    $js = Get-Content $Js -Raw
    Set-Content -Path $Js -Value ($js.Replace("EDITOR_TAB_HEIGHT={normal:35", "EDITOR_TAB_HEIGHT={normal:40")) -NoNewline -Encoding UTF8
    Write-Host "Tab height patched 35->40."
  }
}

# ---------- 4. fix product.json checksums ----------
if (Test-Path $Prod) {
  $prod = Get-Content $Prod -Raw | ConvertFrom-Json
  if ($prod.PSObject.Properties.Name -contains "checksums") {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $changed = 0
    foreach ($p in $prod.checksums.PSObject.Properties) {
      $file = Join-Path (Join-Path $AppRoot "out") $p.Name
      if (Test-Path $file) {
        $hash = $sha.ComputeHash([System.IO.File]::ReadAllBytes($file))
        $new = [Convert]::ToBase64String($hash).TrimEnd("=")
        if ($p.Value -ne $new) { $prod.checksums.($p.Name) = $new; $changed++ }
      }
    }
    if ($changed -gt 0) {
      $prod | ConvertTo-Json -Depth 100 | Set-Content -Path $Prod -Encoding UTF8
      Write-Host "Fixed $changed checksum(s)."
    }
  }
}

Write-Host "Done. Restart $($Target.Name) to see the changes."
Write-Host "Note: editor updates overwrite these files - just re-run this installer."

<#
  StackRivals - collect test diagnostics (READ-ONLY).

  Copies ONLY StackRivals data into a ZIP on your Desktop:
    - the installed StackRivals version per WoW client (from StackRivals.toc)
    - StackRivals' own saved data (WTF\Account\<acc>\SavedVariables\StackRivals.lua),
      with the account folder name replaced by "account1", "account2", ...
    - lines that mention StackRivals from the client's Logs\FrameXML.log (if that log exists)

  It never writes to, renames or deletes anything in your World of Warcraft folder, and it does
  not copy Config.wtf, other add-ons' data, character names, chat logs or account files.

  Run (PowerShell):
    powershell -ExecutionPolicy Bypass -File .\collect-diagnostics.ps1
    powershell -ExecutionPolicy Bypass -File .\collect-diagnostics.ps1 -WowRoot "D:\Games\World of Warcraft"
#>
param(
  [string]$WowRoot = "C:\Program Files (x86)\World of Warcraft"
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $WowRoot)) {
  Write-Host "World of Warcraft folder not found: $WowRoot  (use -WowRoot to point to it)"
  exit 1
}

$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$work = Join-Path ([System.IO.Path]::GetTempPath()) "StackRivals-diagnostics-$stamp"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$report = New-Object System.Collections.Generic.List[string]
$report.Add("StackRivals diagnostics $stamp (local time)")
$report.Add("WoW folder: $WowRoot")
$report.Add("")

$clients = Get-ChildItem -LiteralPath $WowRoot -Directory | Where-Object { $_.Name -match '^_.+_$' }
foreach ($c in $clients) {
  $name = $c.Name.Trim('_')
  $report.Add("[$name]")
  $toc = Join-Path $c.FullName "Interface\AddOns\StackRivals\StackRivals.toc"
  if (Test-Path -LiteralPath $toc) {
    $ver = (Select-String -LiteralPath $toc -Pattern '^## Version:' | Select-Object -First 1).Line
    $ifc = (Select-String -LiteralPath $toc -Pattern '^## Interface:' | Select-Object -First 1).Line
    $report.Add("  installed: $ver")
    $report.Add("  $ifc")
  } else {
    $report.Add("  StackRivals not installed")
  }

  $acct = Join-Path $c.FullName "WTF\Account"
  if (Test-Path -LiteralPath $acct) {
    $n = 0
    foreach ($a in (Get-ChildItem -LiteralPath $acct -Directory | Sort-Object Name)) {
      $sv = Join-Path $a.FullName "SavedVariables\StackRivals.lua"
      if (Test-Path -LiteralPath $sv) {
        $n++
        $dest = Join-Path $work "$name-account$n-StackRivals.lua"
        Copy-Item -LiteralPath $sv -Destination $dest
        $info = Get-Item -LiteralPath $sv
        $report.Add(("  saved data account{0}: {1} bytes, last written {2}" -f $n, $info.Length, $info.LastWriteTime))
      }
    }
    if ($n -eq 0) { $report.Add("  no StackRivals saved data yet (play once and log out or /reload)") }
  }

  $log = Join-Path $c.FullName "Logs\FrameXML.log"
  if (Test-Path -LiteralPath $log) {
    $hits = Select-String -LiteralPath $log -Pattern 'StackRivals' | ForEach-Object { $_.Line }
    if ($hits) {
      $hits | Set-Content -LiteralPath (Join-Path $work "$name-FrameXML-StackRivals.txt") -Encoding UTF8
      $report.Add("  FrameXML.log: $($hits.Count) StackRivals line(s) copied")
    }
  }
  $report.Add("")
}

$report | Set-Content -LiteralPath (Join-Path $work "report.txt") -Encoding UTF8
$desktop = [Environment]::GetFolderPath("Desktop")
$zip = Join-Path $desktop "StackRivals-diagnostics-$stamp.zip"
Compress-Archive -Path (Join-Path $work "*") -DestinationPath $zip -Force
Remove-Item -LiteralPath $work -Recurse -Force
Write-Host ""
Write-Host ($report -join [Environment]::NewLine)
Write-Host "Saved: $zip"
Write-Host "Nothing in your WoW folder was changed."

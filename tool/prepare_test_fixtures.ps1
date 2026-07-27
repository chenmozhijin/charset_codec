#!/usr/bin/env pwsh
# SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
  [string]$LockPath = 'tool/fixtures.lock.json',
  [string]$FixturesRoot = (Join-Path $PSScriptRoot '..\test\.fixtures'),
  [switch]$SkipIntegrityCheck
)

$ErrorActionPreference = 'Stop'

function Resolve-ProjectPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $projectRoot $Path))
}

function Get-PythonInvocation {
  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($null -ne $python) {
    return @{
      Exe = $python.Source
      PrefixArgs = @()
    }
  }
  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($null -ne $py) {
    return @{
      Exe = $py.Source
      PrefixArgs = @('-3')
    }
  }
  throw 'Python runtime not found. Install python or py launcher first.'
}

function Invoke-PythonScript([string]$ScriptPath, [string[]]$ScriptArgs) {
  $cmd = Get-PythonInvocation
  & $cmd.Exe @($cmd.PrefixArgs) $ScriptPath @ScriptArgs
}

function Download-Archive([string]$Name, [hashtable]$Source, [string]$TempDir) {
  $url = [string]$Source.url
  $hash = [string]$Source.sha256
  $archivePath = Join-Path $TempDir "$Name.zip"
  Write-Host "Downloading $Name from $url"
  Invoke-WebRequest -Uri $url -OutFile $archivePath
  if (-not [string]::IsNullOrWhiteSpace($hash)) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash.ToLowerInvariant()
    if ($actual -ne $hash.ToLowerInvariant()) {
      throw "SHA256 mismatch for ${Name}: expected=$hash actual=$actual"
    }
  } else {
    Write-Warning "$Name has no SHA256 in lock file; skip hash verification."
  }
  $extractDir = Join-Path $TempDir "$Name-extracted"
  Expand-Archive -Path $archivePath -DestinationPath $extractDir -Force
  $hint = [string]$Source.archiveRootHint
  if (-not [string]::IsNullOrWhiteSpace($hint)) {
    $hintPath = Join-Path $extractDir $hint
    if (Test-Path -LiteralPath $hintPath -PathType Container) {
      return $hintPath
    }
  }
  $children = Get-ChildItem -LiteralPath $extractDir -Directory
  if ($children.Count -eq 1) {
    return $children[0].FullName
  }
  throw "Unable to determine extracted root for $Name"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

$lockAbs = Resolve-ProjectPath $LockPath
$fixturesAbs = Resolve-ProjectPath $FixturesRoot
if (-not (Test-Path -LiteralPath $lockAbs -PathType Leaf)) {
  throw "Lock file not found: $lockAbs"
}

$lockJson = Get-Content -LiteralPath $lockAbs -Raw | ConvertFrom-Json -AsHashtable
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("charset-codec-fixtures-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
  $pyRoot = Download-Archive -Name 'pythontestdotnet' -Source $lockJson.sources.pythontestdotnet -TempDir $tempDir

  if (Test-Path -LiteralPath $fixturesAbs) {
    Remove-Item -LiteralPath $fixturesAbs -Recurse -Force
  }
  New-Item -ItemType Directory -Path $fixturesAbs | Out-Null

  $rawMapsDir = Join-Path $fixturesAbs 'codecmaps/raw'
  New-Item -ItemType Directory -Path $rawMapsDir -Force | Out-Null
  $unicodeRoot = Join-Path $pyRoot 'www/unicode'
  if (-not (Test-Path -LiteralPath $unicodeRoot -PathType Container)) {
    throw "Unicode map root not found: $unicodeRoot"
  }

  foreach ($spec in $lockJson.codeMaps) {
    $src = Join-Path $unicodeRoot ([string]$spec.filename)
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
      throw "Required code map file missing: $src"
    }
    Copy-Item -LiteralPath $src -Destination (Join-Path $rawMapsDir ([string]$spec.filename)) -Force
  }

  $preparePy = Resolve-ProjectPath 'tool/prepare_test_fixtures.py'
  if (-not (Test-Path -LiteralPath $preparePy -PathType Leaf)) {
    throw "prepare_test_fixtures.py not found: $preparePy"
  }
  Invoke-PythonScript -ScriptPath $preparePy -ScriptArgs @(
    '--lock', $lockAbs,
    '--fixtures-root', $fixturesAbs,
    '--code-maps-root', $rawMapsDir
  )

  if (-not $SkipIntegrityCheck) {
    $checkPy = Resolve-ProjectPath 'tool/check_fixtures_integrity.py'
    Invoke-PythonScript -ScriptPath $checkPy -ScriptArgs @(
      '--fixtures-root', $fixturesAbs,
      '--lock', $lockAbs
    )
  }

  $fileCount = (Get-ChildItem -LiteralPath $fixturesAbs -File -Recurse | Measure-Object).Count
  Write-Host "Prepared fixtures at: $fixturesAbs"
  Write-Host "File count: $fileCount"
} finally {
  if (Test-Path -LiteralPath $tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force
  }
}

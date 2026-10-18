$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) { throw 'First run setup.ps1.' }
Write-Host 'Little Companion: http://127.0.0.1:8765 — Ctrl+C to stop'
& $python server.py

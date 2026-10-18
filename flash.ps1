param([string]$Port = 'COM3')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$cli = Join-Path $env:LOCALAPPDATA 'Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe'
if (-not (Test-Path -LiteralPath $cli)) { throw 'Arduino CLI not found. Install Arduino IDE and the ESP32 board package.' }
$board = 'esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=16M,PSRAM=opi,PartitionScheme=custom'
& $cli compile --fqbn $board --build-path build firmware\companion
if ($LASTEXITCODE) { throw 'Compile failed' }
& $cli upload --fqbn $board --port $Port --input-dir build firmware\companion
if ($LASTEXITCODE) { throw 'Upload failed' }
Write-Host 'Firmware installed. Disconnect USB from the web page before using boardctl.'

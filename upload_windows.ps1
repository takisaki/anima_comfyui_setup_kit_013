param(
  [Parameter(Mandatory = $true)][string]$Server,
  [int]$Port = 22,
  [string]$SshUser = "root",
  [switch]$WithExtras
)
# Upload the migration kit to the cloud server (Windows).
#   .\upload_windows.ps1 -Server 1.2.3.4
#   .\upload_windows.ps1 -Server 1.2.3.4 -Port 34567
#   .\upload_windows.ps1 -Server 1.2.3.4 -WithExtras
# Requires OpenSSH client (built into Windows 10/11).
# NOTE: this file is intentionally ASCII-only. Windows PowerShell 5.1 reads
# non-ASCII .ps1 files as ANSI and corrupts them, so do not add Chinese here.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$target = $SshUser + "@" + $Server
function Send-File($local, $remote) {
    if (-not (Test-Path $local)) { throw "missing file: $local" }
    $size = [math]::Round((Get-Item $local).Length / 1MB, 1)
    Write-Host ("[upload] " + $local + " (" + $size + " MB) -> " + $target + ":" + $remote) -ForegroundColor Cyan
    scp -P $Port $local ($target + ":" + $remote)
    if ($LASTEXITCODE -ne 0) { throw "scp failed: $local" }
}
Write-Host ("server : " + $Server) -ForegroundColor Gray
Write-Host ("port   : " + $Port) -ForegroundColor Gray
Write-Host ("user   : " + $SshUser) -ForegroundColor Gray
Write-Host ""
Send-File "cloud-kit.zip" "/root/"
if ($WithExtras) {
    $extras = Join-Path (Split-Path $PSScriptRoot -Parent) "extras_optional.tar"
    if (Test-Path $extras) {
        Send-File $extras "/root/"
    } else {
        Write-Host ("[skip] not found: " + $extras) -ForegroundColor Yellow
    }
}
Write-Host ""
Write-Host "Upload done. Now run on the server:" -ForegroundColor Green
Write-Host ("  ssh -p " + $Port + " " + $target)
Write-Host "  apt-get update"
Write-Host "  apt-get install -y unzip"
Write-Host "  unzip -q /root/cloud-kit.zip -d /root/kit"
Write-Host "  cd /root/kit"
Write-Host "  bash setup_all.sh"

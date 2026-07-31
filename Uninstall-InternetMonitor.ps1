[CmdletBinding()]
param([switch]$RemoveHistory)

$ErrorActionPreference = "Stop"
$InstallPath = "C:\InternetMonitor"
$tasks = @("InternetMonitor - Coleta")

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Execute este desinstalador como administrador."
}

foreach ($task in $tasks) {
    $existing = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $task -Confirm:$false
    }
}

$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutNames = @(
    "Internet Monitor.lnk",
    "Internet Monitor - Testar agora.lnk",
    "Internet Monitor - Configurar.lnk",
    "Internet Monitor - Escolher servidor.lnk"
)
foreach ($name in $shortcutNames) {
    $shortcut = Join-Path $desktop $name
    if (Test-Path -LiteralPath $shortcut) {
        Remove-Item -LiteralPath $shortcut -Force
    }
}

if (Test-Path -LiteralPath $InstallPath) {
    if ($RemoveHistory) {
        $resolved = (Resolve-Path -LiteralPath $InstallPath).Path
        if ($resolved -ne "C:\InternetMonitor") {
            throw "Caminho inesperado; remoção cancelada: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
        Write-Host "Monitor e histórico removidos." -ForegroundColor Green
    }
    else {
        Get-ChildItem -LiteralPath $InstallPath -Force |
            Where-Object { $_.Name -notin @("data", "logs") } |
            Remove-Item -Recurse -Force
        Write-Host "Monitor removido. Histórico preservado em C:\InternetMonitor\data." -ForegroundColor Green
    }
}

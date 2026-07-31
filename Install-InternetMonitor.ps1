[CmdletBinding()]
param(
    [ValidateRange(15, 1440)]
    [int]$IntervalMinutes = 60,
    [switch]$NoInitialTest,
    [switch]$DoNotOpenDashboard,
    # Última saída caso a verificação de assinatura falhe em um ambiente legítimo.
    [switch]$SkipSignatureCheck
)

$ErrorActionPreference = "Stop"
$InstallPath = "C:\InternetMonitor"
$TaskCollector = "InternetMonitor - Coleta"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Execute este instalador como administrador."
    }
}

# O WinGet publica em Links\ um atalho (symlink ou stub) que não carrega a assinatura
# da Ookla. Copiar e verificar esse atalho não faz sentido: é preciso chegar ao
# executável real dentro de Packages\.
function Resolve-RealPath([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $Path }
    if ($item.LinkType -and $item.Target) {
        $target = @($item.Target)[0]
        if ($target) {
            if (-not [System.IO.Path]::IsPathRooted($target)) {
                $target = Join-Path (Split-Path -Parent $item.FullName) $target
            }
            if (Test-Path -LiteralPath $target) {
                return (Resolve-Path -LiteralPath $target).Path
            }
        }
    }
    return $item.FullName
}

# O binário roda como SYSTEM a cada coleta e costuma vir de uma pasta gravável pelo
# usuário (LOCALAPPDATA), então vale confirmar sua procedência. A Ookla não assina o
# speedtest.exe do CLI e ele não traz VersionInfo, então não há como exigir Authenticode:
# a garantia criptográfica dessa cadeia é a verificação de hash que o WinGet faz contra
# o manifesto oficial na instalação. O que dá para checar aqui é que, se houver
# assinatura, ela seja da Ookla, e que o executável se identifique como Speedtest.
function Assert-Speedtest([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path

    if ($signature.Status -eq "Valid") {
        if ($signature.SignerCertificate.Subject -notmatch "Ookla") {
            throw @"
O speedtest.exe encontrado está assinado por outra entidade.

  Arquivo:   $Path
  Assinante: $($signature.SignerCertificate.Subject)

Como esse binário seria executado como SYSTEM, a instalação foi interrompida.
"@
        }
        Write-Host "  Assinatura verificada: $($signature.SignerCertificate.Subject.Split(',')[0])"
        return
    }

    # Uma assinatura presente porém quebrada (HashMismatch, NotTrusted) indica
    # adulteração; ausência de assinatura é o comportamento normal da Ookla.
    if ($signature.Status -ne "NotSigned") {
        throw @"
A assinatura digital do speedtest.exe está inválida.

  Arquivo: $Path
  Status:  $($signature.Status)

Como esse binário seria executado como SYSTEM, a instalação foi interrompida.
"@
    }

    $banner = ""
    try {
        $banner = (& $Path --version 2>&1 | Select-Object -First 1) -join " "
    }
    catch {
        throw "Não foi possível executar $Path para identificá-lo: $($_.Exception.Message)"
    }
    if ("$banner" -notmatch "Speedtest by Ookla") {
        throw @"
O arquivo encontrado não se identifica como Speedtest da Ookla.

  Arquivo:  $Path
  Resposta: $banner

Como esse binário seria executado como SYSTEM, a instalação foi interrompida.
Baixe o Speedtest CLI em https://www.speedtest.net/apps/cli, coloque o
speedtest.exe em "$InstallPath\bin" e execute o instalador novamente.
"@
    }
    Write-Host "  Identificado: $banner"
}

function Find-Speedtest {
    $known = @(
        (Join-Path $InstallPath "bin\speedtest.exe"),
        "$env:ProgramFiles\Speedtest CLI\speedtest.exe",
        "$env:ProgramFiles\Ookla\Speedtest CLI\speedtest.exe"
    )
    foreach ($candidate in $known) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    # Antes dos atalhos: aqui está o binário assinado que o WinGet extraiu.
    $roots = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
        "$env:ProgramFiles\WinGet\Packages"
    )
    foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root) {
            $found = Get-ChildItem -LiteralPath $root -Filter speedtest.exe -File -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }

    $link = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\speedtest.exe"
    if (Test-Path -LiteralPath $link) { return (Resolve-RealPath $link) }

    $command = Get-Command speedtest.exe -ErrorAction SilentlyContinue
    if ($command) { return (Resolve-RealPath $command.Source) }

    return $null
}

# Os scripts em $InstallPath rodam como SYSTEM a cada coleta. Se a pasta herdar as
# permissões frouxas da raiz do disco, um usuário sem privilégio pode substituir o
# conteúdo de Collect-Internet.ps1 e escalar privilégio. Aqui a herança é quebrada e
# a escrita é liberada apenas onde o painel realmente precisa gravar.
function Set-InstallAcl([string]$Path) {
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)

    $accounts = @(
        @{ Sid = "S-1-5-18"; Rights = "FullControl" }          # SYSTEM
        @{ Sid = "S-1-5-32-544"; Rights = "FullControl" }      # Administradores
        @{ Sid = "S-1-5-32-545"; Rights = "ReadAndExecute" }   # Usuários
    )
    foreach ($account in $accounts) {
        $identity = New-Object System.Security.Principal.SecurityIdentifier($account.Sid)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity, $account.Rights, "ContainerInherit, ObjectInherit", "None", "Allow"
        )))
    }
    $acl.SetOwner((New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Grant-UserWrite([string]$Path) {
    $acl = Get-Acl -LiteralPath $Path
    $identity = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
    $inheritance = if (Test-Path -LiteralPath $Path -PathType Container) {
        "ContainerInherit, ObjectInherit"
    } else {
        "None"
    }
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $identity, "Modify", $inheritance, "None", "Allow"
    )))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

Assert-Administrator

Write-Step "Preparando as pastas"
$directories = @(
    $InstallPath,
    (Join-Path $InstallPath "bin"),
    (Join-Path $InstallPath "dashboard"),
    (Join-Path $InstallPath "data"),
    (Join-Path $InstallPath "logs")
)
foreach ($directory in $directories) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

Write-Step "Aplicando as permissões"
Set-InstallAcl $InstallPath
# O atalho da Área de Trabalho regenera o painel com a conta do usuário, então estas
# três pastas precisam ser graváveis sem privilégio elevado.
foreach ($writable in @("data", "logs", "dashboard")) {
    Grant-UserWrite (Join-Path $InstallPath $writable)
}

Write-Step "Preservando o histórico existente"
$legacyCsv = Join-Path $InstallPath "historico-internet.csv"
$currentCsv = Join-Path $InstallPath "data\historico-internet.csv"
if ((Test-Path -LiteralPath $legacyCsv) -and -not (Test-Path -LiteralPath $currentCsv)) {
    $legacyRows = @(Import-Csv -LiteralPath $legacyCsv)
    $migratedRows = foreach ($row in $legacyRows) {
        [PSCustomObject][ordered]@{
            DataHora = $row.DataHora
            DownloadMbps = $row.DownloadMbps
            UploadMbps = $row.UploadMbps
            PingMs = $row.PingMs
            JitterMs = $row.JitterMs
            PerdaPacotesPct = $row.PerdaPacotesPct
            ISP = $row.ISP
            Servidor = $row.Servidor
            LocalServidor = $row.LocalServidor
            URLResultado = $row.URLResultado
            Status = if ($row.Status) { $row.Status } else { "Sucesso" }
            Mensagem = ""
        }
    }
    if ($migratedRows.Count) {
        $migratedRows | Export-Csv -LiteralPath $currentCsv -NoTypeInformation -Encoding UTF8
    }
    Copy-Item -LiteralPath $legacyCsv -Destination (Join-Path $InstallPath "data\historico-legado-backup.csv") -Force
}

Write-Step "Instalando o Speedtest CLI"
$speedtestPath = Find-Speedtest
if (-not $speedtestPath) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "WinGet não foi encontrado. Atualize o 'Instalador de Aplicativo' pela Microsoft Store e tente novamente."
    }

    & $winget.Source install --id Ookla.Speedtest.CLI -e --silent `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "O WinGet não conseguiu instalar Ookla.Speedtest.CLI (código $LASTEXITCODE)."
    }
    $speedtestPath = Find-Speedtest
}
if (-not $speedtestPath) {
    throw "O Speedtest CLI foi instalado, mas speedtest.exe não foi localizado."
}

$speedtestPath = Resolve-RealPath $speedtestPath
if ($SkipSignatureCheck) {
    Write-Warning "Verificação de procedência ignorada por -SkipSignatureCheck."
}
else {
    Assert-Speedtest $speedtestPath
}

$bundledSpeedtest = Join-Path $InstallPath "bin\speedtest.exe"
$sourceSpeedtest = (Resolve-Path -LiteralPath $speedtestPath).Path
$destinationSpeedtest = if (Test-Path -LiteralPath $bundledSpeedtest) {
    (Resolve-Path -LiteralPath $bundledSpeedtest).Path
} else {
    $bundledSpeedtest
}
if (-not [string]::Equals($sourceSpeedtest, $destinationSpeedtest, [StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item -LiteralPath $sourceSpeedtest -Destination $bundledSpeedtest -Force
}

Write-Step "Copiando os componentes"
$sourcePath = Join-Path $PSScriptRoot "src"
$files = @(
    "Collect-Internet.ps1",
    "Configure-Monitor.ps1",
    "List-Servers.ps1",
    "Open-Dashboard.ps1",
    "Test-Now.ps1",
    "Update-DashboardData.ps1"
)
foreach ($file in $files) {
    Copy-Item -LiteralPath (Join-Path $sourcePath $file) -Destination (Join-Path $InstallPath $file) -Force
}
Copy-Item -Path (Join-Path $sourcePath "dashboard\*") -Destination (Join-Path $InstallPath "dashboard") -Recurse -Force

$configPath = Join-Path $InstallPath "config.json"

# Começa dos padrões da versão nova e sobrescreve com o que já estava instalado: assim
# uma atualização preserva os ajustes do usuário e ainda ganha as chaves novas.
$config = Get-Content -LiteralPath (Join-Path $sourcePath "config.json") -Raw -Encoding UTF8 |
    ConvertFrom-Json
if (Test-Path -LiteralPath $configPath) {
    $installed = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in $installed.PSObject.Properties) {
        $config | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
    }
}
$previousInterval = if ($null -ne $config.collectionIntervalMinutes) {
    [double]$config.collectionIntervalMinutes
} else {
    60
}
$previousAutomaticStale = [math]::Ceiling($previousInterval * 2.5)
$staleWasAutomatic = ($null -eq $config.staleAfterMinutes) -or
    ([math]::Abs([double]$config.staleAfterMinutes - $previousAutomaticStale) -lt 0.001)

$config | Add-Member -NotePropertyName "collectionIntervalMinutes" -NotePropertyValue $IntervalMinutes -Force
if ($staleWasAutomatic) {
    $config | Add-Member -NotePropertyName "staleAfterMinutes" `
        -NotePropertyValue ([int][math]::Ceiling($IntervalMinutes * 2.5)) -Force
}
$config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding UTF8
# config.json não é executado; liberar a escrita evita exigir elevação para ajustar
# os limites do painel.
Grant-UserWrite $configPath

Write-Step "Criando as tarefas automáticas"
$powerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$collectorAction = New-ScheduledTaskAction -Execute $powerShellExe -Argument (
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $InstallPath "Collect-Internet.ps1")
)
# Trigger diário repetindo a cada N minutos ao longo de 24 horas. Uma repetição única
# de duração muito longa (anos) é aceita pelo cmdlet mas o Agendador pode descartá-la,
# deixando a tarefa sem registro nenhum.
$collectorTrigger = New-ScheduledTaskTrigger -Daily -At "00:00"
$collectorTrigger.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Hours 24)).Repetition
$collectorPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$collectorSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $TaskCollector -Action $collectorAction -Trigger $collectorTrigger `
    -Principal $collectorPrincipal -Settings $collectorSettings -Description (
        "Executa o Speedtest CLI a cada $IntervalMinutes minutos e grava o histórico local."
    ) -Force | Out-Null

# O registro pode ser aceito e mesmo assim não resultar em tarefa: sem esta conferência
# a instalação terminaria "com sucesso" e nenhuma coleta automática aconteceria.
$registered = Get-ScheduledTask -TaskName $TaskCollector -ErrorAction SilentlyContinue
if (-not $registered) {
    throw "A tarefa '$TaskCollector' não foi criada. A coleta automática não funcionaria."
}
Write-Host ("  Tarefa registrada: {0} (a cada {1} min, estado {2})" -f
    $TaskCollector, $IntervalMinutes, $registered.State)

Write-Step "Criando os atalhos na Área de Trabalho"
$desktop = [Environment]::GetFolderPath("Desktop")
$shell = New-Object -ComObject WScript.Shell

function New-DesktopShortcut([string]$Name, [string]$Script, [string]$WindowStyle, [int]$IconIndex) {
    $shortcut = $shell.CreateShortcut((Join-Path $desktop $Name))
    $shortcut.TargetPath = $powerShellExe
    $shortcut.Arguments = '-NoProfile -WindowStyle {0} -ExecutionPolicy Bypass -File "{1}"' -f
        $WindowStyle, (Join-Path $InstallPath $Script)
    $shortcut.WorkingDirectory = $InstallPath
    $shortcut.IconLocation = "$env:SystemRoot\System32\netshell.dll,$IconIndex"
    $shortcut.Save()
}

New-DesktopShortcut "Internet Monitor.lnk" "Open-Dashboard.ps1" "Hidden" 0
# A medição sob demanda e a configuração são interativas, então a janela fica visível.
New-DesktopShortcut "Internet Monitor - Testar agora.lnk" "Test-Now.ps1" "Normal" 4
New-DesktopShortcut "Internet Monitor - Configurar.lnk" "Configure-Monitor.ps1" "Normal" 22

# O atalho de servidor foi absorvido pelo menu de configuração.
$obsoleteShortcut = Join-Path $desktop "Internet Monitor - Escolher servidor.lnk"
if (Test-Path -LiteralPath $obsoleteShortcut) {
    Remove-Item -LiteralPath $obsoleteShortcut -Force -ErrorAction SilentlyContinue
}

if (-not $NoInitialTest) {
    Write-Step "Executando a primeira medição (pode levar alguns minutos)"
    & $powerShellExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $InstallPath "Collect-Internet.ps1")
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "A primeira medição falhou. Consulte C:\InternetMonitor\logs\coleta-erros.log."
    }
}

Write-Step "Iniciando o dashboard"
if (-not $DoNotOpenDashboard) {
    & (Join-Path $InstallPath "Open-Dashboard.ps1")
}

Write-Host "`nInstalação concluída." -ForegroundColor Green
Write-Host "Coleta: a cada $IntervalMinutes minutos, como SYSTEM (sem senha)."
Write-Host "Dashboard: C:\InternetMonitor\dashboard\index.html"
Write-Host "Histórico: C:\InternetMonitor\data\historico-internet.csv"

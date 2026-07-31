[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = "Stop"
# Invocado com -File, o PowerShell avalia os valores padrão dos parâmetros antes de
# popular $PSScriptRoot, e o padrão sairia vazio. No corpo do script ele já é válido.
if (-not $Root) { $Root = $PSScriptRoot }

$DataPath = Join-Path $Root "data"
$LogPath = Join-Path $Root "logs"
$CsvPath = Join-Path $DataPath "historico-internet.csv"
$ConfigPath = Join-Path $Root "config.json"
$SpeedtestExe = Join-Path $Root "bin\speedtest.exe"
$DashboardUpdater = Join-Path $Root "Update-DashboardData.ps1"
$mutex = $null
$hasLock = $false

function Write-ErrorLog([string]$Message) {
    try {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        $cleanMessage = $Message -replace '[\r\n]+', ' '
        $logLine = "{0} - {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $cleanMessage
        Add-Content -LiteralPath (Join-Path $LogPath "coleta-erros.log") -Value $logLine -Encoding UTF8
    }
    catch {
        # Sem permissão de escrita no log; o erro ainda será gravado no CSV.
    }
}

# Ordem canônica das colunas do histórico. Alterar esta lista dispara a migração
# automática do CSV existente em Save-Record.
$Schema = @(
    "DataHora", "DownloadMbps", "UploadMbps", "PingMs", "JitterMs", "PerdaPacotesPct",
    "ISP", "Servidor", "ServidorID", "LocalServidor", "Conexao", "URLResultado",
    "Status", "Mensagem"
)

function ConvertTo-SchemaRow([psobject]$Row) {
    $ordered = [ordered]@{}
    foreach ($column in $Schema) {
        $property = $Row.PSObject.Properties[$column]
        $ordered[$column] = if ($property) { $property.Value } else { "" }
    }
    [PSCustomObject]$ordered
}

function Test-CurrentSchema {
    $firstRow = Import-Csv -LiteralPath $CsvPath | Select-Object -First 1
    if (-not $firstRow) { return $false }
    $columns = @($firstRow.PSObject.Properties.Name)
    if ($columns.Count -ne $Schema.Count) { return $false }
    for ($i = 0; $i -lt $Schema.Count; $i++) {
        if ($columns[$i] -ne $Schema[$i]) { return $false }
    }
    return $true
}

function Save-Record([psobject]$Record) {
    New-Item -ItemType Directory -Path $DataPath -Force | Out-Null
    $row = ConvertTo-SchemaRow $Record

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        $row | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
        return
    }

    if (Test-CurrentSchema) {
        $row | Export-Csv -LiteralPath $CsvPath -Append -NoTypeInformation -Encoding UTF8
        return
    }

    # Histórico gravado por uma versão anterior: reescreve no schema atual, sem perder
    # nenhuma linha e guardando um backup antes de substituir o arquivo.
    Write-ErrorLog "Migrando o histórico para o schema atual do CSV."
    $migrated = @(Import-Csv -LiteralPath $CsvPath | ForEach-Object { ConvertTo-SchemaRow $_ })
    $migrated += $row
    Copy-Item -LiteralPath $CsvPath -Destination (Join-Path $DataPath "historico-internet.bak.csv") -Force
    $temporary = Join-Path $DataPath ("historico-{0}.tmp" -f [guid]::NewGuid())
    try {
        $migrated | Export-Csv -LiteralPath $temporary -NoTypeInformation -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $CsvPath -Force
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

# A coleta roda ora como SYSTEM, ora como o usuário, e cada contexto pode ter uma
# cultura diferente. Sem formatação invariante, o mesmo CSV acabaria misturando
# "599,56" e "599.56".
function Format-Metric($Value) {
    if ($null -eq $Value) { return "" }
    return [math]::Round([double]$Value, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-FixedServerId {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return 0 }
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $id = [int]$config.servidorFixoId
        if ($id -gt 0) { return $id }
    }
    catch {
        Write-ErrorLog ("Não foi possível ler o servidor fixo do config.json: {0}" -f $_.Exception.Message)
    }
    return 0
}

# Executa o Speedtest e devolve stdout. Com um servidor fixo configurado, uma
# indisponibilidade momentânea dele interromperia o monitoramento por completo, então
# o teste é refeito em modo automático antes de considerar a coleta perdida.
function Invoke-Speedtest([int]$ServerId) {
    $tempOut = Join-Path $env:TEMP ("internet-monitor-{0}.json" -f [guid]::NewGuid())
    $tempErr = Join-Path $env:TEMP ("internet-monitor-{0}.log" -f [guid]::NewGuid())
    try {
        $arguments = @("--accept-license", "--accept-gdpr", "--format=json")
        if ($ServerId -gt 0) { $arguments += "--server-id=$ServerId" }

        $process = Start-Process -FilePath $SpeedtestExe -ArgumentList $arguments `
            -NoNewWindow -PassThru -RedirectStandardOutput $tempOut -RedirectStandardError $tempErr

        # Cachear o handle garante que ExitCode fique disponível após a saída do processo.
        $process.Handle | Out-Null

        if (-not $process.WaitForExit(480000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "O Speedtest excedeu o limite de 8 minutos."
        }
        $process.WaitForExit()
        # O Speedtest emite UTF-8 sem BOM e o padrão do Get-Content no PS 5.1 é ANSI,
        # o que corromperia acentos em nomes de servidor e cidade.
        $stdout = Get-Content -LiteralPath $tempOut -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $tempErr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($process.ExitCode -ne 0) {
            throw "Speedtest retornou código $($process.ExitCode): $stderr"
        }
        if (-not $stdout) { throw "O Speedtest não retornou dados." }
        return $stdout
    }
    finally {
        Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempErr -Force -ErrorAction SilentlyContinue
    }
}

# Wi-Fi e Ethernet produzem resultados muito diferentes; sem essa informação um
# resultado ruim é ambíguo.
function Get-ConnectionKind {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
            Sort-Object -Property RouteMetric |
            Select-Object -First 1
        if (-not $route) { return "" }
        $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop
        if (-not $adapter) { return "" }
        if ($adapter.PhysicalMediaType -like "*802.11*") { return "Wi-Fi" }
        if ($adapter.PhysicalMediaType -like "*802.3*" -or $adapter.MediaType -eq "802.3") {
            return "Ethernet"
        }
        return [string]$adapter.InterfaceDescription
    }
    catch {
        return ""
    }
}

function Update-Dashboard {
    try {
        if (-not (Test-Path -LiteralPath $DashboardUpdater)) {
            throw "Atualizador do dashboard não encontrado em $DashboardUpdater"
        }
        & $DashboardUpdater -Root $Root
    }
    catch {
        Write-ErrorLog ("Falha ao atualizar o dashboard: {0}" -f $_.Exception.Message)
    }
}

# As colunas ausentes são preenchidas por ConvertTo-SchemaRow.
function New-FailureRecord([string]$Message) {
    [PSCustomObject]@{
        DataHora = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Conexao = Get-ConnectionKind
        Status = "Erro"
        Mensagem = $Message
    }
}

try {
    # O namespace Global\ exige SeCreateGlobalPrivilege. Quando o script roda sob uma
    # conta padrão (teste manual), recorremos a um mutex local em vez de abortar.
    try {
        $mutex = New-Object System.Threading.Mutex($false, "Global\InternetMonitorCollector")
    }
    catch {
        $mutex = New-Object System.Threading.Mutex($false, "Local\InternetMonitorCollector")
    }
    $hasLock = $mutex.WaitOne(0)
    if (-not $hasLock) { exit 0 }
    if (-not (Test-Path -LiteralPath $SpeedtestExe)) {
        throw "speedtest.exe não encontrado em $SpeedtestExe"
    }

    $fixedServerId = Get-FixedServerId
    try {
        $stdout = Invoke-Speedtest -ServerId $fixedServerId
    }
    catch {
        if ($fixedServerId -le 0) { throw }
        Write-ErrorLog (
            "O servidor fixo {0} falhou ({1}). Refazendo o teste em modo automático." -f
            $fixedServerId, ($_.Exception.Message -replace '[\r\n]+', ' ')
        )
        $stdout = Invoke-Speedtest -ServerId 0
    }

    $result = $stdout | ConvertFrom-Json

    $record = [PSCustomObject][ordered]@{
        DataHora = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        DownloadMbps = Format-Metric ([double]$result.download.bandwidth * 8 / 1000000)
        UploadMbps = Format-Metric ([double]$result.upload.bandwidth * 8 / 1000000)
        PingMs = Format-Metric $result.ping.latency
        JitterMs = Format-Metric $result.ping.jitter
        PerdaPacotesPct = Format-Metric $result.packetLoss
        ISP = [string]$result.isp
        Servidor = [string]$result.server.name
        ServidorID = [string]$result.server.id
        LocalServidor = [string]$result.server.location
        Conexao = Get-ConnectionKind
        URLResultado = [string]$result.result.url
        Status = "Sucesso"
        Mensagem = ""
    }
    Save-Record $record
    Update-Dashboard
}
catch {
    $message = $_.Exception.Message -replace '[\r\n]+', ' '
    Write-ErrorLog $message
    try {
        Save-Record (New-FailureRecord -Message $message)
        Update-Dashboard
    }
    catch {
        Write-ErrorLog ("Falha ao registrar o erro no histórico: {0}" -f $_.Exception.Message)
    }
    exit 1
}
finally {
    if ($mutex) {
        if ($hasLock) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

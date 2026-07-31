# Internet Monitor para Windows

Mede a sua conexão de tempos em tempos com o Speedtest CLI da Ookla, guarda o
histórico em CSV e mostra tudo em um painel local — inclusive **quanto da
velocidade contratada o seu provedor está realmente entregando**, segundo os
limites da Resolução Anatel 574/2011.

Roda inteiramente na sua máquina: nenhuma porta é aberta, nenhum dado é enviado
a lugar nenhum.

## Por que existe

Reclamar de internet lenta sem dados é uma discussão perdida. Com algumas
centenas de medições carimbadas, a conversa com o provedor muda de figura: o
painel mostra em que horários a conexão degrada, com que frequência ela cai e se
a média do período fica abaixo do mínimo que a Anatel exige.

## Requisitos

- Windows 10 ou 11
- Windows PowerShell 5.1 ou superior
- WinGet (já incluso no Windows 10/11 atualizado)
- Conta de administrador **apenas durante a instalação**

Depois de instalado, o monitor roda como `SYSTEM`. Sua conta do Windows não
precisa ter senha.

## Instalação

1. Baixe e extraia o repositório.
2. Clique com o botão direito em `Instalar.cmd`.
3. Escolha **Executar como administrador** e confirme a janela do Windows.
4. Aguarde a conclusão. A primeira medição pode levar alguns minutos.

Três atalhos são criados na Área de Trabalho:

| Atalho | O que faz |
|---|---|
| **Internet Monitor** | Abre o painel com o histórico |
| **Internet Monitor - Testar agora** | Executa uma medição imediata e abre o painel |
| **Internet Monitor - Configurar** | Menu para ajustar intervalo, plano, servidor e limites |

Você não precisa abrir a pasta de instalação nem o HTML manualmente: o primeiro
atalho já faz isso, atualizando os dados antes de exibir o painel.

> **Consumo de dados:** cada Speedtest transfere uma quantidade relevante de
> dados — em um link de 500 Mbps, tipicamente entre 500 MB e 1,5 GB. No intervalo
> padrão de 60 minutos isso pode passar de 20 GB por dia. Em conexões com
> franquia, aumente o intervalo.

## Conformidade com o contrato

Informe o seu plano em `C:\InternetMonitor\config.json`:

```json
{
  "provedorContratado": "Vivo Fibra",
  "planoContratado": "Plano 700 Mega",
  "contratadoDownloadMbps": 700,
  "contratadoUploadMbps": 350
}
```

O painel passa a exibir dois indicadores por sentido, conforme a Resolução
574/2011:

- **Velocidade média** do período deve alcançar no mínimo **80%** da contratada.
- **Velocidade instantânea** deve alcançar **40%** da contratada em pelo menos
  **95%** das medições.

Deixe as velocidades em `0` para ocultar o painel. `provedorContratado` e
`planoContratado` são apenas rótulos: identificam o plano no painel e não
influenciam nenhum cálculo. O provedor realmente detectado em cada medição é
gravado à parte, na coluna `ISP` do CSV.

## Exportar o relatório em PDF

Duas formas, ambas produzindo um PDF pronto para anexar em protocolo de
reclamação:

- No painel, botão **Exportar PDF** e, na janela de impressão, escolha
  "Salvar como PDF".
- Pelo atalho **Internet Monitor - Configurar**, opção 6, escolhendo o período.
  O arquivo é gravado na Área de Trabalho e aberto em seguida.

O documento traz o plano contratado, o período e a quantidade de medições, um
resumo estatístico com **mínimo, p05, mediana, média, p95 e máximo** de cada
métrica, o painel de conformidade, os gráficos e a tabela de medições.

Os percentis importam mais que a média para avaliar um provedor: uma conexão que
entrega bem quase o tempo todo e desaba no horário de pico mantém uma média
confortável, e é o p05 que expõe a queda.

A geração automática usa o Microsoft Edge (ou o Chrome) em segundo plano. Se
nenhum dos dois for encontrado, o painel é aberto para você usar a impressão do
navegador.

## Fixar o servidor de teste

Por padrão o Speedtest escolhe o servidor "mais próximo" a cada execução. Isso
atrapalha a comparação ao longo do tempo: uma queda no gráfico pode ser
degradação real da sua conexão **ou** apenas outro servidor tendo sido
escolhido.

Use o atalho **Internet Monitor - Configurar**, opção 4, para listar os
servidores próximos e fixar um deles. Ou informe o ID direto na configuração:

```json
{
  "servidorFixoId": 12345
}
```

Use `0` para voltar à escolha automática. Se o servidor fixado estiver
indisponível no momento da coleta, o teste é refeito automaticamente em modo
automático e o desvio fica registrado em `logs\coleta-erros.log` — assim uma
manutenção no servidor não interrompe o monitoramento.

## Uso

- Os botões 24h, 7 dias, 30 dias e Tudo mudam o período analisado.
- Faixas verticais avermelhadas nos gráficos marcam coletas que falharam.
- **Apenas falhas** filtra a tabela para investigar problemas.
- **Abrir CSV** dá acesso ao histórico completo.
- O painel se atualiza sozinho, preservando o período selecionado.

Arquivos gerados:

| Caminho | Conteúdo |
|---|---|
| `C:\InternetMonitor\data\historico-internet.csv` | Histórico completo |
| `C:\InternetMonitor\logs\coleta-erros.log` | Erros de coleta |
| `C:\InternetMonitor\config.json` | Limites e velocidade contratada |

A tarefa agendada aparece como `InternetMonitor - Coleta`.

## Alterar a frequência das medições

Pelo atalho **Internet Monitor - Configurar**, opção 1. O Windows pedirá
confirmação de administrador, porque alterar a tarefa agendada exige elevação.

O intervalo aceito vai de 15 a 1440 minutos; 60 ou 120 são boas escolhas.
Intervalos curtos consomem franquia rapidamente — veja o aviso de consumo acima.
O limite do aviso de "dados desatualizados" acompanha o intervalo
automaticamente, a menos que `staleAfterMinutes` tenha sido personalizado.

O mesmo menu ajusta o plano contratado, o servidor de teste e os limites do
painel, sem precisar editar JSON à mão.

Pela linha de comando, reinstalando:

```powershell
.\Install-InternetMonitor.ps1 -IntervalMinutes 120
```

Isso preserva o histórico e as configurações existentes.

## Limites do painel

Ainda em `config.json`, para destaque visual dos cartões:

```json
{
  "downloadMinMbps": 500,
  "uploadMinMbps": 500,
  "pingMaxMs": 50,
  "jitterMaxMs": 20,
  "packetLossMaxPct": 1
}
```

Esses valores não alteram a medição.

## Estrutura do projeto

```
Instalar.cmd / Desinstalar.cmd     Atalhos com elevação automática
Install-InternetMonitor.ps1        Instalador: pastas, ACLs, tarefa e atalhos
Uninstall-InternetMonitor.ps1      Desinstalador (preserva o histórico)
src/
  Collect-Internet.ps1             Executa o Speedtest e grava o CSV
  Update-DashboardData.ps1         Converte o CSV em data.js
  Open-Dashboard.ps1               Atualiza os dados e abre o painel
  Test-Now.ps1                     Medição sob demanda
  Configure-Monitor.ps1            Menu de configuração
  Export-Report.ps1                Gera o relatório em PDF
  List-Servers.ps1                 Lista e fixa o servidor de teste
  config.json                      Configuração padrão
  dashboard/                       Painel (HTML, CSS e JS sem dependências)
```

## Diagnóstico

| Sintoma | O que verificar |
|---|---|
| Painel não abre | Execute o atalho novamente |
| Sem medições novas | Abra **Configurar** e veja o estado da coleta automática |
| Coleta aparece como "configurada" sem detalhes | A tarefa foi criada por uma versão anterior e não é legível sem elevação; use a opção 1 uma vez para regravá-la |
| Status `Erro` no painel | Consulte `logs\coleta-erros.log` |
| Limites não mudaram | Feche a aba e reabra pelo atalho |
| Resultado baixo isolado | Outro equipamento, Wi-Fi, VPN ou backup pode ter usado a conexão. A coluna **Conexão** ajuda a distinguir Wi-Fi de cabo |

Perda de pacotes em um teste isolado costuma ser transitória; investigue quando
for recorrente.

## Desinstalação

Clique com o botão direito em `Desinstalar.cmd` e escolha **Executar como
administrador**. O histórico é preservado em `C:\InternetMonitor\data`.

Para remover tudo, inclusive o histórico:

```powershell
.\Uninstall-InternetMonitor.ps1 -RemoveHistory
```

## Privacidade e segurança

- O painel é um arquivo local aberto via `file://`. Nenhuma porta de rede é
  aberta e nada é enviado para fora da máquina.
- O CSV registra provedor, servidor usado e a URL do resultado na Ookla, mas
  **não** armazena o seu IP público.
- A pasta de instalação recebe permissões explícitas: apenas administradores e
  `SYSTEM` podem alterar os scripts, que são executados com privilégio elevado.
- A procedência do `speedtest.exe` é conferida antes do uso. A Ookla **não**
  assina digitalmente o executável do CLI, então a garantia criptográfica dessa
  cadeia é a verificação de hash que o WinGet faz contra o manifesto oficial
  durante a instalação. O instalador recusa o binário se ele estiver assinado por
  outra entidade, se a assinatura estiver quebrada ou se ele não se identificar
  como Speedtest da Ookla.

O `speedtest.exe` é distribuído pela Ookla e está sujeito aos termos dela; a
instalação aceita a licença e o GDPR de forma não interativa.

## Licença

[MIT](LICENSE).

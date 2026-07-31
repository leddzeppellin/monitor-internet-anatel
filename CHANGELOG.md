# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [1.2.1] - 2026-07-30

### Corrigido

- A instalação era interrompida com `NotSigned` ao encontrar o Speedtest CLI. A
  verificação exigia assinatura Authenticode da Ookla, mas a Ookla não assina o
  executável do CLI — e o caminho conferido era o atalho de 0 byte que o WinGet
  publica em `Links\`, não o binário real. Agora o atalho é resolvido para o
  arquivo em `Packages\` e a procedência é confirmada de outra forma: assinatura
  de terceiro ou quebrada continua bloqueando, e um binário sem assinatura
  precisa se identificar como Speedtest da Ookla ao ser executado.
- `-SkipSignatureCheck` foi adicionado como saída para ambientes onde a
  verificação não se aplica.

## [1.2.0] - 2026-07-30

### Adicionado

- **Servidor de teste fixo** (`servidorFixoId`): mantém a mesma referência entre
  as medições, para que variações no gráfico reflitam a conexão e não a troca de
  servidor. Se o servidor fixado estiver indisponível, o teste é refeito em modo
  automático e o desvio é registrado no log.
- Atalho **Internet Monitor - Escolher servidor**, que lista os servidores
  próximos com seus IDs e grava a escolha na configuração.
- Campos `provedorContratado` e `planoContratado`, exibidos no painel de
  conformidade para identificar o plano avaliado.

## [1.1.0] - 2026-07-30

### Adicionado

- Painel de **conformidade do contrato** com os limites da Resolução Anatel
  574/2011: 80% da velocidade contratada na média do período e 40% em pelo menos
  95% das medições individuais. Configure `contratadoDownloadMbps` e
  `contratadoUploadMbps` para ativar.
- **Faixas de falha nos gráficos**: períodos com coleta malsucedida aparecem como
  faixas verticais, em vez de sumirem da série.
- Atalho **Internet Monitor - Testar agora** para medição sob demanda, sem
  precisar de PowerShell elevado.
- Colunas `Conexao` (Wi-Fi ou Ethernet) e `ServidorID` no histórico, com migração
  automática do CSV das versões anteriores.
- Filtro **Apenas falhas** e links para o resultado na Ookla na tabela.
- Aviso quando o painel exibe apenas parte do histórico.

### Corrigido

- Scripts gravados sem BOM faziam o Windows PowerShell 5.1 interpretá-los como
  ANSI, corrompendo todo texto acentuado das mensagens.
- Histórico com uma única medição renderizava gráficos vazios: um caminho de
  ponto único não produz traço no canvas. Agora há marcadores.
- O painel recarregava a página inteira a cada minuto, descartando o período
  selecionado e a posição de rolagem. A atualização passou a ser incremental.
- `Collect-Internet.ps1` abortava sem registrar nada quando executado por uma
  conta sem privilégio, por causa do mutex no namespace `Global\`.
- `ExitCode` do Speedtest podia ficar indisponível após a saída do processo.
- Rótulo do eixo Y dos gráficos aparecia cortado quando o valor tinha três
  dígitos.
- Uma atualização por cima não adicionava as chaves novas de configuração.

### Segurança

- A pasta de instalação passou a receber ACL explícita, sem herdar as permissões
  da raiz do disco. Isso fecha a possibilidade de uma conta sem privilégio
  substituir um script executado como `SYSTEM` a cada coleta.
- A procedência do `speedtest.exe` é conferida antes de ele ser copiado para a
  pasta de instalação. Veja a correção em 1.2.1.

## [1.0.0]

- Coleta periódica via Speedtest CLI, histórico em CSV e painel local.

# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

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
- A assinatura digital do `speedtest.exe` é verificada antes de ele ser copiado
  para a pasta de instalação.

## [1.0.0]

- Coleta periódica via Speedtest CLI, histórico em CSV e painel local.

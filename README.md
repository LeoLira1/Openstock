# OpenStock

Aplicativo Flutter para acompanhar, em reais, uma carteira com ações, FIIs,
ETFs e BDRs da B3 e ativos negociados nos Estados Unidos.

## Recursos

- cadastro de ativo, quantidade, preço médio e câmbio médio de compra;
- patrimônio, resultado diário e resultado total em reais e percentual;
- conversão automática de posições em dólar para reais;
- histórico diário persistente por ativo, com cache local;
- comparação simultânea entre ativos e a carteira em `1M`, `3M`, `6M`, `1A`,
  `5A` e `Máx`;
- comparação da carteira com o CDI, com rentabilidade sem o efeito dos aportes;
- renda fixa (CDB, LCI, LCA) corrigida sozinha por percentual do CDI ou taxa
  prefixada, com valor líquido de imposto de renda;
- modo comparativo normalizado em 0% e modo de preço nominal;
- detalhes do ativo, linha do preço médio e visão relativa ao preço médio;
- sincronização opcional por Turso, mantendo SQLite como cache offline;
- atualização manual, gesto de puxar para atualizar, edição, exclusão confirmada
  e preço manual de contingência.

## Comparar

A aba **Comparar** aceita qualquer combinação dos ativos cadastrados e a série
**Minha carteira**. Em **Desempenho %**, cada série usa o primeiro fechamento
real disponível no período como 0%:

```text
(fechamento / fechamento_inicial - 1) * 100
```

Não há interpolação de fins de semana, feriados ou pregões ausentes. Ao tocar ou
arrastar no gráfico, a data é ajustada a um fechamento real e cada série mostra
o último fechamento válido naquela data. A série da carteira usa exclusivamente
os snapshots diários reais; o aplicativo não cria patrimônio retroativo.

## Carteira contra o CDI

A série **CDI** usa a taxa diária publicada pelo Banco Central (série 12 do SGS,
em % ao dia útil). O aplicativo guarda as taxas como vieram, em
`cdi_daily_rates`, e acumula o índice na leitura:

```text
índice_do_dia = índice_anterior * (1 + taxa_do_dia / 100)
```

Como o índice é recalculado a cada janela, trocar o período nunca deixa dois
trechos do gráfico com bases diferentes. Dias sem divulgação não são preenchidos.

O cartão **Carteira × CDI** mede as duas séries entre as mesmas datas — a janela
em que ambas existem — e a rentabilidade da carteira é ponderada no tempo:

```text
retorno_do_intervalo = patrimônio_final / (patrimônio_inicial + aporte) - 1
```

O aporte de cada intervalo é a variação do valor aplicado entre dois snapshots,
então depositar dinheiro não aparece como valorização e sacar não aparece como
prejuízo. O cartão mostra a diferença em pontos percentuais e quanto a carteira
rendeu em relação ao CDI. Sem dois snapshots reais no período não há comparação:
nenhum trecho é extrapolado para preencher o número.

O CDI é um índice acumulado, sem preço em reais, então ele aparece apenas no
modo **Desempenho %**.

No modo **Preço**, ativos em BRL e USD mantêm sua moeda de negociação. Para
comparação neutra de moeda, use **Desempenho %**. A linha da carteira permanece
em BRL e segue a conversão USD/BRL usada no painel.

## Renda fixa

Um título entra pela aba **Ativos** escolhendo **Renda fixa** no formulário:
tipo (CDB, LCI, LCA ou outro), apelido, valor aplicado, indexador, taxa, data da
aplicação e vencimento opcional. Não há cotação a buscar — o valor é calculado
a partir do que foi aplicado.

Para **% do CDI**, cada dia útil multiplica o valor pelo fator do mercado:

```text
fator_do_dia = 1 + (taxa_cdi_do_dia / 100) * (percentual / 100)
```

O percentual incide sobre a taxa do dia, não sobre o fator acumulado — é a
convenção usada nos contratos de CDB, LCI e LCA.

Para **prefixado**, a taxa contratada é convertida para o dia útil na convenção
de 252 dias:

```text
fator_do_dia = (1 + taxa_anual / 100) ^ (1 / 252)
```

O calendário de dias úteis é a própria série do CDI: o Banco Central publica a
taxa exatamente nos dias em que o título rende, então feriados e fins de semana
ficam de fora sem precisar de uma tabela de feriados no aplicativo. O dia da
aplicação ainda não rende e o rendimento para no vencimento. Como o Banco
Central divulga a taxa com um dia de atraso, a tela do título mostra até quando
ele está corrigido.

A tela do título também estima o **valor líquido**. LCI e LCA são isentas para
pessoa física; nos demais vale a tabela regressiva sobre o rendimento, pelo
prazo em dias corridos desde a aplicação:

| Prazo | Alíquota |
| --- | --- |
| até 180 dias | 22,5% |
| 181 a 360 dias | 20% |
| 361 a 720 dias | 17,5% |
| acima de 720 dias | 15% |

O título guarda o valor aplicado no preço médio com quantidade 1, de modo que
patrimônio, custo e resultado da carteira usam o mesmo cálculo dos demais
ativos, e a comparação com o CDI passa a incluir a renda fixa.

IPCA+ ainda não é suportado: o IPCA é mensal e entra nos títulos com defasagem,
o que exigiria uma regra própria de pro rata em vez de reaproveitar o calendário
diário usado aqui.

## Histórico e cache

Os fechamentos ficam em `asset_price_history`, com chave única
`(asset_key, price_date)`. Inserções repetidas fazem UPSERT e não duplicam dias.
O primeiro acesso a um período faz backfill pelo provedor; acessos recentes usam
o SQLite e atualizações posteriores pedem apenas a parte incremental quando o
cache já cobre o início do período. A validade do cache de consulta é de seis
horas.

As identidades sincronizadas são lógicas e estáveis, por exemplo `b3:PRIO3` e
`usa:AAPL`; IDs autoincrementais continuam existindo somente como detalhe local.

## Fontes de cotação

- B3 atual: [brapi.dev](https://brapi.dev/), com fallback `.SA` para a consulta
  pública já usada pelo projeto;
- Estados Unidos atual: Finnhub quando configurada, com a consulta pública já
  existente como contingência;
- histórico diário B3/EUA e USD/BRL: endpoint público de gráficos do Yahoo
  Finance já utilizado pelo aplicativo;
- manual: preço informado pelo usuário, sem histórico inventado.

As cotações podem ter atraso e não devem ser usadas para execução de ordens. O
OpenStock é uma ferramenta de acompanhamento, não uma recomendação financeira.

## Configurar o Turso

1. Crie ou escolha um banco no Turso.
2. Obtenha a URL HTTP/libSQL do banco e crie um token de banco de dados.
3. No OpenStock, abra **Ajustes > Turso > Configurar Turso**.
4. Informe `TURSO_DATABASE_URL` (aceita `libsql://`, `turso://` ou `https://`)
   e `TURSO_AUTH_TOKEN`.
5. Toque em **Validar e sincronizar** e repita com as mesmas credenciais no
   segundo aparelho.

As credenciais ficam no `flutter_secure_storage` de cada aparelho e nunca são
incluídas no repositório ou nas tabelas sincronizadas. O app usa o endpoint
oficial `/v2/pipeline` com Bearer Authentication. As tabelas remotas são criadas
com `CREATE TABLE/INDEX IF NOT EXISTS`.

### Como a sincronização funciona

- SQLite é gravado primeiro e o aplicativo continua funcionando sem internet;
- alterações pendentes são enviadas quando a conexão volta ou ao tocar em
  **Sincronizar agora**;
- ativos, quantidade, preço médio, câmbio médio, histórico e snapshots são
  sincronizados;
- cada alteração possui `updated_at`; o registro mais novo vence e uma versão
  remota mais antiga não sobrescreve silenciosamente a local;
- exclusões usam tombstone (`deleted_at`), sem apagar imediatamente o registro
  sincronizado;
- histórico e snapshots usam chaves naturais únicas, evitando duplicidade;
- chaves Finnhub e Turso são segredos locais e não são sincronizadas.

## Banco local e migração

O banco é atualizado de forma versionada. A migração adiciona colunas e cria as
tabelas/índices abaixo sem `DROP TABLE`, sem limpeza geral e sem recriar o banco:

- `asset_price_history`;
- `history_fetch_state`;
- `sync_state`;
- colunas de identidade, timestamps, tombstone e status de sincronização;
- `transactions`, reservada para evolução futura e ainda sem efeito nos
  cálculos atuais.

## Funcionamento offline e estados parciais

Sem conexão, a carteira, as últimas cotações e todo histórico já armazenado
continuam disponíveis. Uma falha de provedor fica associada apenas ao ativo que
falhou; as outras séries continuam no gráfico. O app diferencia carregamento,
ausência de histórico, erro de cotação e erro de sincronização.

## Limitações conhecidas

- **Minha carteira** começa no primeiro snapshot real disponível; alterações
  antigas de quantidade não são reconstruídas sem transações históricas;
- a resolução de conflitos usa `updated_at` e pressupõe relógios razoavelmente
  ajustados nos aparelhos;
- ativos manuais não recebem histórico de mercado automaticamente;
- disponibilidade e profundidade de `Máx` dependem do provedor e do símbolo;
- a integração pública de histórico pode sofrer atraso ou indisponibilidade do
  provedor.

## Desenvolvimento

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

O workflow `release.yml` analisa, testa, gera o APK e publica automaticamente a
release `v1.1.0` após a integração das alterações na branch `main`.

## Licença e atribuição

Distribuído sob GNU AGPL-3.0-or-later. A arquitetura de provedores foi adaptada
com crédito ao projeto
[Open-Dev-Society/OpenStock](https://github.com/Open-Dev-Society/OpenStock),
também AGPL-3.0. Consulte `LICENSE` e `NOTICE.md`.

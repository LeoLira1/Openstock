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

No modo **Preço**, ativos em BRL e USD mantêm sua moeda de negociação. Para
comparação neutra de moeda, use **Desempenho %**. A linha da carteira permanece
em BRL e segue a conversão USD/BRL usada no painel.

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

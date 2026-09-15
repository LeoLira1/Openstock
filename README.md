# OpenStock

Aplicativo Flutter para acompanhar, em reais, uma carteira com ações, FIIs, ETFs e BDRs da B3 e ativos negociados nos Estados Unidos.

## Recursos

- cadastro de ativo, quantidade, preço médio e câmbio médio de compra;
- patrimônio total, resultado do dia e lucro acumulado em reais e percentual;
- conversão automática de posições em dólar para reais;
- gráfico consolidado da carteira e composição por ativo;
- atualização manual, gesto de puxar para atualizar e cache local;
- edição, exclusão confirmada e preço manual de contingência;
- banco SQLite privado no aparelho, sem conta e sem segredo embutido.

## Fontes de cotação

- B3: [brapi.dev](https://brapi.dev/) com fallback automático `.SA` para símbolos fora da lista de demonstração, como `PRIO3` e `BBAS3`;
- Estados Unidos: Finnhub, seguindo a integração do projeto Open-Dev-Society/OpenStock; a chave gratuita é inserida no app e protegida pelo Android;
- histórico internacional e USD/BRL: consulta pública de gráfico, para símbolos como `VOO`, `TSLA` e `XOM`;
- Manual: o usuário informa o preço atual quando preferir ou se uma fonte estiver indisponível.

As cotações podem ter atraso e não devem ser usadas para execução de ordens. O app é uma ferramenta de acompanhamento, não uma recomendação de investimento.

Sem uma chave Finnhub, o app mantém uma fonte pública alternativa para que o
acompanhamento internacional não pare. Nenhum segredo é incluído no APK.

## Licença e atribuição

Distribuído sob GNU AGPL-3.0-or-later. A arquitetura de provedores foi adaptada
com crédito ao projeto [Open-Dev-Society/OpenStock](https://github.com/Open-Dev-Society/OpenStock),
também AGPL-3.0. Consulte `LICENSE` e `NOTICE.md`.

## Desenvolvimento

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

O workflow `release.yml` valida o projeto, gera um APK universal e publica a release `v1.0.4`.

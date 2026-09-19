import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/controllers/portfolio_controller.dart';
import 'package:openstock/models/investment_asset.dart';

void main() {
  const asset = InvestmentAsset(
    symbol: 'PRIO3',
    name: 'PRIO',
    market: AssetMarket.b3,
    currency: AssetCurrency.brl,
    quantity: 267,
    averagePrice: 42.38,
    currentPrice: 63.24,
    previousClose: 63.29,
  );

  final hoje = DateTime(2026, 9, 18, 17, 5);
  final ontem = DateTime(2026, 9, 17, 18);

  MarketQuote quote({
    required double current,
    required double previousClose,
    DateTime? priceDate,
  }) =>
      MarketQuote(
        current: current,
        previousClose: previousClose,
        history: const [],
        priceDate: priceDate ?? hoje,
      );

  test('fonte sem véspera não apaga o fechamento já apurado', () {
    final controller = PortfolioController();

    // A consulta pública devolve o próprio preço quando não sabe a véspera.
    final semVespera = quote(current: 63.24, previousClose: 63.24);

    expect(
      controller.fechamentoAnterior(asset, semVespera, hoje),
      63.29,
      reason: 'o resultado do dia mudava a cada atualização sem o preço mudar',
    );
  });

  test('fonte com véspera manda no valor', () {
    final controller = PortfolioController();
    final comVespera = quote(current: 63.24, previousClose: 63.29);

    expect(controller.fechamentoAnterior(asset, comVespera, hoje), 63.29);

    // E uma correção da fonte é aceita.
    final corrigida = quote(current: 63.24, previousClose: 63.30);
    expect(controller.fechamentoAnterior(asset, corrigida, hoje), 63.30);
  });

  test('em um pregão novo a véspera antiga não é preservada', () {
    final controller = PortfolioController();
    final semVespera = quote(current: 63.24, previousClose: 63.24);

    // O último preço conhecido era de ontem: hoje a véspera é outra, e manter
    // a antiga mediria a variação contra o dia errado.
    expect(controller.fechamentoAnterior(asset, semVespera, ontem), 63.24);
  });

  test('sem nada guardado, vale o que a fonte disser', () {
    final controller = PortfolioController();
    const novo = InvestmentAsset(
      symbol: 'SLCE3',
      name: 'SLCE3',
      market: AssetMarket.b3,
      currency: AssetCurrency.brl,
      quantity: 31,
      averagePrice: 18,
    );
    final semVespera = quote(current: 17.68, previousClose: 17.68);

    expect(controller.fechamentoAnterior(novo, semVespera, hoje), 17.68);
  });
}

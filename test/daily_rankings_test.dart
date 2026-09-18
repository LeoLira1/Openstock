import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/controllers/portfolio_controller.dart';
import 'package:openstock/models/investment_asset.dart';

InvestmentAsset _asset(
  String symbol, {
  required double current,
  required double previous,
  double quantity = 1,
}) =>
    InvestmentAsset(
      symbol: symbol,
      name: symbol,
      market: AssetMarket.b3,
      currency: AssetCurrency.brl,
      quantity: quantity,
      averagePrice: previous,
      currentPrice: current,
      previousClose: previous,
    );

void main() {
  test('separa altas e baixas e ordena ambas pela variação percentual', () {
    final controller = PortfolioController()
      ..assets = [
        _asset('ALTA2', current: 110, previous: 100),
        _asset('BAIXA1', current: 95, previous: 100, quantity: 1000),
        _asset('ESTAVEL', current: 100, previous: 100),
        _asset('ALTA1', current: 120, previous: 100),
        _asset('BAIXA2', current: 80, previous: 100),
      ];
    for (final asset in controller.assets) {
      controller.quoteDates[asset.syncKey] = DateTime.now();
    }

    expect(controller.dayGainers.map((asset) => asset.symbol),
        ['ALTA1', 'ALTA2']);
    expect(controller.dayLosers.map((asset) => asset.symbol),
        ['BAIXA2', 'BAIXA1']);
  });

  test('tamanho da posição não altera o ranking percentual', () {
    final controller = PortfolioController()
      ..assets = [
        _asset('POSICAO_GRANDE', current: 101, previous: 100, quantity: 1000),
        _asset('MAIOR_ALTA', current: 105, previous: 100),
      ];
    for (final asset in controller.assets) {
      controller.quoteDates[asset.syncKey] = DateTime.now();
    }

    expect(controller.dayGainers.first.symbol, 'MAIOR_ALTA');
    expect(controller.assetDayResult(controller.dayGainers.last), 1000);
  });

  test('ranking em reais considera o impacto total de cada posição', () {
    final controller = PortfolioController()
      ..assets = [
        _asset('ALTA_PERCENTUAL', current: 110, previous: 100),
        _asset('ALTA_EM_REAIS', current: 101, previous: 100, quantity: 1000),
        _asset('BAIXA_PERCENTUAL', current: 90, previous: 100),
        _asset('BAIXA_EM_REAIS', current: 99, previous: 100, quantity: 1000),
      ];
    for (final asset in controller.assets) {
      controller.quoteDates[asset.syncKey] = DateTime.now();
    }

    expect(controller.dayGainers.first.symbol, 'ALTA_PERCENTUAL');
    expect(controller.dayGainersByValue.first.symbol, 'ALTA_EM_REAIS');
    expect(controller.dayLosers.first.symbol, 'BAIXA_PERCENTUAL');
    expect(controller.dayLosersByValue.first.symbol, 'BAIXA_EM_REAIS');
  });

  test('antes de um novo pregão não repete a variação de ontem', () {
    final asset = _asset('PRIO3', current: 44, previous: 42);
    final controller = PortfolioController()..assets = [asset];

    controller.quoteDates[asset.syncKey] =
        DateTime.now().subtract(const Duration(days: 1));

    expect(controller.assetDayResult(asset), 0);
    expect(controller.dayPercent, 0);
    expect(controller.dayChangeLabel, 'mercados fechados');
  });

  test('a variação começa quando a cotação pertence ao pregão de hoje', () {
    final asset = _asset('PRIO3', current: 44, previous: 42);
    final controller = PortfolioController()..assets = [asset];

    controller.quoteDates[asset.syncKey] = DateTime.now();

    expect(controller.assetDayPercent(asset), closeTo(4.7619, 0.0001));
    expect(controller.dayChangeLabel, 'hoje');
  });

  test('câmbio isolado não cria alta antes do pregão americano', () {
    final asset = InvestmentAsset(
      symbol: 'AMD',
      name: 'AMD',
      market: AssetMarket.usa,
      currency: AssetCurrency.usd,
      quantity: 1,
      averagePrice: 100,
      currentPrice: 100,
      previousClose: 100,
    );
    final controller = PortfolioController()
      ..assets = [asset]
      ..dollarQuote = MarketQuote(
        current: 5.15,
        previousClose: 5.14,
        history: const [],
        priceDate: DateTime.now(),
      );
    controller.quoteDates[asset.syncKey] =
        DateTime.now().subtract(const Duration(days: 1));

    expect(controller.assetDayPercent(asset), 0);
  });
}

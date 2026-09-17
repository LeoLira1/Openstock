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

    expect(controller.dayGainers.first.symbol, 'ALTA_PERCENTUAL');
    expect(controller.dayGainersByValue.first.symbol, 'ALTA_EM_REAIS');
    expect(controller.dayLosers.first.symbol, 'BAIXA_PERCENTUAL');
    expect(controller.dayLosersByValue.first.symbol, 'BAIXA_EM_REAIS');
  });
}

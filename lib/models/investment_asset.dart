enum AssetMarket { b3, usa, manual }

enum AssetCurrency { brl, usd }

class InvestmentAsset {
  const InvestmentAsset({
    this.id,
    required this.symbol,
    required this.name,
    required this.market,
    required this.currency,
    required this.quantity,
    required this.averagePrice,
    this.averageExchangeRate = 1,
    this.currentPrice,
    this.previousClose,
    this.updatedAt,
  });

  final int? id;
  final String symbol;
  final String name;
  final AssetMarket market;
  final AssetCurrency currency;
  final double quantity;
  final double averagePrice;
  final double averageExchangeRate;
  final double? currentPrice;
  final double? previousClose;
  final DateTime? updatedAt;

  bool get hasQuote => currentPrice != null;

  InvestmentAsset copyWith({
    int? id,
    String? symbol,
    String? name,
    AssetMarket? market,
    AssetCurrency? currency,
    double? quantity,
    double? averagePrice,
    double? averageExchangeRate,
    double? currentPrice,
    double? previousClose,
    DateTime? updatedAt,
  }) {
    return InvestmentAsset(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      market: market ?? this.market,
      currency: currency ?? this.currency,
      quantity: quantity ?? this.quantity,
      averagePrice: averagePrice ?? this.averagePrice,
      averageExchangeRate: averageExchangeRate ?? this.averageExchangeRate,
      currentPrice: currentPrice ?? this.currentPrice,
      previousClose: previousClose ?? this.previousClose,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'symbol': symbol,
        'name': name,
        'market': market.name,
        'currency': currency.name,
        'quantity': quantity,
        'average_price': averagePrice,
        'average_exchange_rate': averageExchangeRate,
        'current_price': currentPrice,
        'previous_close': previousClose,
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory InvestmentAsset.fromMap(Map<String, Object?> map) {
    return InvestmentAsset(
      id: map['id'] as int?,
      symbol: map['symbol'] as String,
      name: map['name'] as String,
      market: AssetMarket.values.byName(map['market'] as String),
      currency: AssetCurrency.values.byName(map['currency'] as String),
      quantity: (map['quantity'] as num).toDouble(),
      averagePrice: (map['average_price'] as num).toDouble(),
      averageExchangeRate:
          (map['average_exchange_rate'] as num?)?.toDouble() ?? 1,
      currentPrice: (map['current_price'] as num?)?.toDouble(),
      previousClose: (map['previous_close'] as num?)?.toDouble(),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.parse(map['updated_at'] as String),
    );
  }
}

class PricePoint {
  const PricePoint(this.date, this.value);

  final DateTime date;
  final double value;
}

class MarketQuote {
  const MarketQuote({
    required this.current,
    required this.previousClose,
    required this.history,
  });

  final double current;
  final double previousClose;
  final List<PricePoint> history;
}


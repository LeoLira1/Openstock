enum AssetMarket { b3, usa, manual }

enum AssetCurrency { brl, usd }

class InvestmentAsset {
  const InvestmentAsset({
    this.id,
    this.stableKey,
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
    this.createdAt,
    this.deletedAt,
  });

  final int? id;
  final String? stableKey;
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
  final DateTime? createdAt;
  final DateTime? deletedAt;

  String get syncKey => stableKey ?? buildAssetKey(market, symbol);

  bool get hasQuote => currentPrice != null;

  InvestmentAsset copyWith({
    int? id,
    String? stableKey,
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
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return InvestmentAsset(
      id: id ?? this.id,
      stableKey: stableKey ?? this.stableKey,
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
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'stable_key': syncKey,
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
        'created_at': createdAt?.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };

  factory InvestmentAsset.fromMap(Map<String, Object?> map) {
    return InvestmentAsset(
      id: map['id'] as int?,
      stableKey: map['stable_key'] as String?,
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
      createdAt: map['created_at'] == null
          ? null
          : DateTime.parse(map['created_at'] as String),
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.parse(map['deleted_at'] as String),
    );
  }
}

String buildAssetKey(AssetMarket market, String symbol) {
  final normalized = symbol.trim().toUpperCase().replaceAll('.SA', '');
  return '${market.name}:$normalized';
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
    this.historySource = 'unknown',
  });

  final double current;
  final double previousClose;
  final List<PricePoint> history;
  final String historySource;
}

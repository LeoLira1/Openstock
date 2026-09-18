enum AssetMarket { b3, usa, manual, fixedIncome }

enum AssetCurrency { brl, usd }

/// Tipo do título de renda fixa, que decide a tributação do rendimento.
enum FixedIncomeKind {
  cdb('CDB'),
  lci('LCI'),
  lca('LCA'),
  other('Outro');

  const FixedIncomeKind(this.label);
  final String label;

  /// LCI e LCA são isentas de imposto de renda para pessoa física.
  bool get taxExempt => this == FixedIncomeKind.lci || this == FixedIncomeKind.lca;
}

/// Como o título se corrige: percentual do CDI ou taxa prefixada ao ano.
enum FixedIncomeIndexer {
  cdi('% do CDI'),
  prefixed('Prefixado (a.a.)');

  const FixedIncomeIndexer(this.label);
  final String label;
}

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
    this.fixedIncomeKind,
    this.indexer,
    this.indexerRate,
    this.applicationDate,
    this.maturityDate,
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

  /// Campos preenchidos somente em [AssetMarket.fixedIncome].
  final FixedIncomeKind? fixedIncomeKind;
  final FixedIncomeIndexer? indexer;

  /// Percentual do CDI (110 para 110% do CDI) ou taxa anual do prefixado.
  final double? indexerRate;
  final DateTime? applicationDate;
  final DateTime? maturityDate;

  final DateTime? updatedAt;
  final DateTime? createdAt;
  final DateTime? deletedAt;

  String get syncKey => stableKey ?? buildAssetKey(market, symbol);

  bool get hasQuote => currentPrice != null;

  bool get isFixedIncome => market == AssetMarket.fixedIncome;

  /// Valor aplicado no título; a renda fixa guarda o principal no preço médio
  /// com quantidade 1, então o mesmo cálculo de custo vale para toda a carteira.
  double get principal => averagePrice * quantity;

  bool get isMatured =>
      maturityDate != null && !DateTime.now().isBefore(maturityDate!);

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
    FixedIncomeKind? fixedIncomeKind,
    FixedIncomeIndexer? indexer,
    double? indexerRate,
    DateTime? applicationDate,
    DateTime? maturityDate,
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
      fixedIncomeKind: fixedIncomeKind ?? this.fixedIncomeKind,
      indexer: indexer ?? this.indexer,
      indexerRate: indexerRate ?? this.indexerRate,
      applicationDate: applicationDate ?? this.applicationDate,
      maturityDate: maturityDate ?? this.maturityDate,
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
        'fixed_income_kind': fixedIncomeKind?.name,
        'indexer': indexer?.name,
        'indexer_rate': indexerRate,
        'application_date': applicationDate?.toIso8601String(),
        'maturity_date': maturityDate?.toIso8601String(),
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
      fixedIncomeKind: _enumOrNull(FixedIncomeKind.values, map['fixed_income_kind']),
      indexer: _enumOrNull(FixedIncomeIndexer.values, map['indexer']),
      indexerRate: (map['indexer_rate'] as num?)?.toDouble(),
      applicationDate: _dateOrNull(map['application_date']),
      maturityDate: _dateOrNull(map['maturity_date']),
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

/// Lê um enum gravado pelo nome, tolerando linha antiga ou valor desconhecido.
T? _enumOrNull<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}

DateTime? _dateOrNull(Object? raw) =>
    raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;

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
    this.priceDate,
  });

  final double current;
  final double previousClose;
  final List<PricePoint> history;
  final String historySource;

  /// Data do pregão ao qual [current] pertence.
  ///
  /// Ela é deliberadamente separada do horário em que o aplicativo fez a
  /// consulta. Antes da abertura, por exemplo, o preço atual ainda pertence ao
  /// pregão anterior e não pode criar um snapshot para o novo dia.
  final DateTime? priceDate;
}

enum InvestmentTransactionType {
  openingPosition('Posição inicial'),
  purchase('Compra'),
  sale('Venda'),
  dividend('Dividendo'),
  interestOnCapital('JCP');

  const InvestmentTransactionType(this.label);
  final String label;

  bool get changesPosition =>
      this == openingPosition || this == purchase || this == sale;

  bool get isIncome => this == dividend || this == interestOnCapital;
}

class InvestmentTransaction {
  const InvestmentTransaction({
    required this.id,
    required this.assetKey,
    required this.type,
    required this.transactionDate,
    required this.createdAt,
    required this.updatedAt,
    this.quantity = 0,
    this.unitPrice = 0,
    this.exchangeRate = 1,
    this.fees = 0,
    this.cashValue = 0,
    this.notes,
    this.deletedAt,
  });

  final String id;
  final String assetKey;
  final InvestmentTransactionType type;
  final double quantity;
  final double unitPrice;
  final double exchangeRate;
  final double fees;
  final double cashValue;
  final DateTime transactionDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  double get grossValue => quantity * unitPrice;

  double get cashValueBrl => cashValue * exchangeRate;

  Map<String, Object?> toMap() => {
        'id': id,
        'asset_key': assetKey,
        'type': type.name,
        'quantity': quantity,
        'price': unitPrice,
        'exchange_rate': exchangeRate,
        'fees': fees,
        'cash_value': cashValue,
        'transaction_date': _dateKey(transactionDate),
        'notes': notes,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  factory InvestmentTransaction.fromMap(Map<String, Object?> map) {
    return InvestmentTransaction(
      id: map['id'] as String,
      assetKey: map['asset_key'] as String,
      type: InvestmentTransactionType.values.byName(map['type'] as String),
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (map['price'] as num?)?.toDouble() ?? 0,
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1,
      fees: (map['fees'] as num?)?.toDouble() ?? 0,
      cashValue: (map['cash_value'] as num?)?.toDouble() ?? 0,
      transactionDate: DateTime.parse(map['transaction_date'] as String),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.parse(map['deleted_at'] as String),
    );
  }
}

class TrackedPosition {
  const TrackedPosition({
    required this.quantity,
    required this.averagePrice,
    required this.averageExchangeRate,
    required this.incomeBrl,
    required this.realizedResultBrl,
  });

  final double quantity;
  final double averagePrice;
  final double averageExchangeRate;
  final double incomeBrl;
  final double realizedResultBrl;
}

TrackedPosition calculateTrackedPosition(
  Iterable<InvestmentTransaction> transactions,
) {
  final ordered = transactions.where((item) => item.deletedAt == null).toList()
    ..sort((a, b) {
      final byDate = a.transactionDate.compareTo(b.transactionDate);
      return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
    });
  var quantity = 0.0;
  var cost = 0.0;
  var costBrl = 0.0;
  var incomeBrl = 0.0;
  var realizedBrl = 0.0;
  for (final item in ordered) {
    if (item.type == InvestmentTransactionType.openingPosition ||
        item.type == InvestmentTransactionType.purchase) {
      final addedCost = item.grossValue + item.fees;
      quantity += item.quantity;
      cost += addedCost;
      costBrl += addedCost * item.exchangeRate;
    } else if (item.type == InvestmentTransactionType.sale && quantity > 0) {
      final sold = item.quantity.clamp(0, quantity).toDouble();
      final average = cost / quantity;
      realizedBrl +=
          ((item.unitPrice - average) * sold - item.fees) * item.exchangeRate;
      final fraction = sold / quantity;
      cost *= 1 - fraction;
      costBrl *= 1 - fraction;
      quantity -= sold;
    } else if (item.type.isIncome) {
      incomeBrl += item.cashValueBrl;
    }
  }
  if (quantity.abs() < 0.0000001) {
    quantity = 0;
    cost = 0;
    costBrl = 0;
  }
  return TrackedPosition(
    quantity: quantity,
    averagePrice: quantity == 0 ? 0 : cost / quantity,
    averageExchangeRate: cost == 0 ? 1 : costBrl / cost,
    incomeBrl: incomeBrl,
    realizedResultBrl: realizedBrl,
  );
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

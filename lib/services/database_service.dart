import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/history_models.dart';
import '../models/investment_asset.dart';
import '../models/investment_transaction.dart';

const databaseVersion = 6;

/// Colunas que a renda fixa acrescenta em `assets`, locais e no Turso.
const fixedIncomeColumns = <String, String>{
  'fixed_income_kind': 'TEXT',
  'indexer': 'TEXT',
  'indexer_rate': 'REAL',
  'application_date': 'TEXT',
  'maturity_date': 'TEXT',
};

class DatabaseService {
  DatabaseService._();
  DatabaseService.forTesting(Database database) : _database = database;

  static final DatabaseService instance = DatabaseService._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      join(root, 'openstock.db'),
      version: databaseVersion,
      onCreate: createSchema,
      onUpgrade: migrateSchema,
    );
    return _database!;
  }

  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE assets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stable_key TEXT NOT NULL,
        symbol TEXT NOT NULL,
        name TEXT NOT NULL,
        market TEXT NOT NULL,
        currency TEXT NOT NULL,
        quantity REAL NOT NULL,
        average_price REAL NOT NULL,
        average_exchange_rate REAL NOT NULL DEFAULT 1,
        current_price REAL,
        previous_close REAL,
        fixed_income_kind TEXT,
        indexer TEXT,
        indexer_rate REAL,
        application_date TEXT,
        maturity_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _createSupportingSchema(db);
  }

  static Future<void> migrateSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, 'assets', 'stable_key', 'TEXT');
      await _addColumnIfMissing(db, 'assets', 'created_at', 'TEXT');
      await _addColumnIfMissing(db, 'assets', 'deleted_at', 'TEXT');
      await _addColumnIfMissing(
          db, 'assets', 'sync_status', 'INTEGER NOT NULL DEFAULT 0');
      final now = DateTime.now().toUtc().toIso8601String();
      await db.rawUpdate('''
        UPDATE assets
        SET stable_key = lower(market) || ':' || upper(replace(symbol, '.SA', '')),
            created_at = COALESCE(created_at, updated_at, ?),
            updated_at = COALESCE(updated_at, ?)
        WHERE stable_key IS NULL OR created_at IS NULL OR updated_at IS NULL
      ''', [now, now]);
      await _addColumnIfMissing(
          db, 'portfolio_snapshots', 'updated_at', 'TEXT');
      await _addColumnIfMissing(db, 'portfolio_snapshots', 'sync_status',
          'INTEGER NOT NULL DEFAULT 0');
      await db.rawUpdate('''
        UPDATE portfolio_snapshots
        SET updated_at = COALESCE(updated_at, created_at)
        WHERE updated_at IS NULL
      ''');
    }
    if (oldVersion < 5) {
      for (final column in fixedIncomeColumns.entries) {
        await _addColumnIfMissing(db, 'assets', column.key, column.value);
      }
    }
    if (oldVersion < 6) {
      // Em versões antigas a tabela ainda pode não existir. A criação é
      // idempotente e acontece antes dos ALTER TABLE não destrutivos.
      await _createSupportingSchema(db);
      await _addColumnIfMissing(
          db, 'transactions', 'cash_value', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'transactions', 'notes', 'TEXT');
      await _addColumnIfMissing(
          db, 'transactions', 'sync_status', 'INTEGER NOT NULL DEFAULT 0');
    }
    await _createSupportingSchema(db);
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  static Future<void> _createSupportingSchema(Database db) async {
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_assets_stable_key
      ON assets(stable_key)''');
    await db
        .execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_assets_symbol_market
      ON assets(symbol, market)''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS portfolio_snapshots(
        snapshot_date TEXT PRIMARY KEY,
        total_brl REAL NOT NULL,
        cost_brl REAL NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''CREATE TABLE IF NOT EXISTS app_state(
      state_key TEXT PRIMARY KEY, state_value TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_price_history(
        asset_key TEXT NOT NULL,
        price_date TEXT NOT NULL,
        close_price REAL NOT NULL,
        currency TEXT NOT NULL,
        source TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(asset_key, price_date)
      )
    ''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_history_asset_date
      ON asset_price_history(asset_key, price_date)''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS history_fetch_state(
        asset_key TEXT NOT NULL,
        period TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        PRIMARY KEY(asset_key, period)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cdi_daily_rates(
        rate_date TEXT PRIMARY KEY,
        daily_percent REAL NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''CREATE TABLE IF NOT EXISTS sync_state(
      state_key TEXT PRIMARY KEY, state_value TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions(
        id TEXT PRIMARY KEY,
        asset_key TEXT NOT NULL,
        type TEXT NOT NULL,
        quantity REAL NOT NULL,
        price REAL NOT NULL,
        exchange_rate REAL,
        fees REAL NOT NULL DEFAULT 0,
        cash_value REAL NOT NULL DEFAULT 0,
        transaction_date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_transactions_asset_date
      ON transactions(asset_key, transaction_date)''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_daily_snapshots(
        asset_key TEXT NOT NULL,
        snapshot_date TEXT NOT NULL,
        quantity REAL NOT NULL,
        average_price REAL NOT NULL,
        exchange_rate REAL NOT NULL,
        current_price REAL NOT NULL,
        value_brl REAL NOT NULL,
        cost_brl REAL NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(asset_key, snapshot_date)
      )
    ''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_asset_snapshots_date
      ON asset_daily_snapshots(snapshot_date)''');
  }

  Future<List<InvestmentAsset>> loadAssets(
      {bool includeDeleted = false}) async {
    final db = await database;
    final rows = await db.query(
      'assets',
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'symbol COLLATE NOCASE',
    );
    return rows.map(InvestmentAsset.fromMap).toList();
  }

  Future<InvestmentAsset> saveAsset(InvestmentAsset asset) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final normalized = asset.copyWith(
      stableKey: asset.syncKey,
      createdAt: asset.createdAt ?? now,
      updatedAt: now,
    );
    final values = normalized.toMap()
      ..remove('id')
      ..['sync_status'] = 0;
    if (asset.id == null) {
      final id = await db.insert('assets', values);
      return normalized.copyWith(id: id);
    }
    await db.update('assets', values, where: 'id = ?', whereArgs: [asset.id]);
    return normalized;
  }

  Future<void> saveQuote(int id, MarketQuote quote) async {
    final db = await database;
    await db.update(
      'assets',
      {
        'current_price': quote.current,
        'previous_close': quote.previousClose,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAsset(int id) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'assets',
      {'deleted_at': now, 'updated_at': now, 'sync_status': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<InvestmentTransaction>> loadTransactions({
    String? assetKey,
    bool includeDeleted = false,
  }) async {
    final db = await database;
    final conditions = <String>[
      if (assetKey != null) 'asset_key = ?',
      if (!includeDeleted) 'deleted_at IS NULL',
    ];
    final rows = await db.query(
      'transactions',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: assetKey == null ? null : [assetKey],
      orderBy: 'transaction_date DESC, created_at DESC',
    );
    return rows.map(InvestmentTransaction.fromMap).toList();
  }

  Future<void> ensureOpeningTransactions(
    Iterable<InvestmentAsset> assets, {
    DateTime? trackingDate,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final day = dateKey(trackingDate ?? now.toLocal());
    await db.transaction((txn) async {
      for (final asset in assets) {
        final existing = await txn.rawQuery(
          'SELECT 1 FROM transactions '
          'WHERE asset_key = ? AND deleted_at IS NULL LIMIT 1',
          [asset.syncKey],
        );
        if (existing.isNotEmpty) continue;
        final opening = InvestmentTransaction(
          id: 'opening:${asset.syncKey}:$day',
          assetKey: asset.syncKey,
          type: InvestmentTransactionType.openingPosition,
          quantity: asset.quantity,
          unitPrice: asset.averagePrice,
          exchangeRate: asset.averageExchangeRate,
          transactionDate: DateTime.parse(day),
          createdAt: now,
          updatedAt: now,
          notes: 'Posição existente no início do rastreamento',
        ).toMap()
          ..['sync_status'] = 0;
        await txn.insert(
          'transactions',
          opening,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> saveTransaction(InvestmentTransaction transaction) async {
    final db = await database;
    final values = transaction.toMap()..['sync_status'] = 0;
    await db.insert(
      'transactions',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateOpeningTransaction(InvestmentAsset asset) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'transactions',
      {
        'quantity': asset.quantity,
        'price': asset.averagePrice,
        'exchange_rate': asset.averageExchangeRate,
        'updated_at': now,
        'sync_status': 0,
      },
      where: 'asset_key = ? AND type = ? AND deleted_at IS NULL',
      whereArgs: [
        asset.syncKey,
        InvestmentTransactionType.openingPosition.name,
      ],
    );
  }

  Future<void> deleteTransaction(String id) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'transactions',
      {'deleted_at': now, 'updated_at': now, 'sync_status': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveAssetDailySnapshot(
    InvestmentAsset asset, {
    required double exchangeRate,
    required double valueBrl,
    required double costBrl,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final day = dateKey(now.toLocal());
    final price = asset.currentPrice ?? asset.averagePrice;
    await db.rawInsert('''
      INSERT INTO asset_daily_snapshots(
        asset_key, snapshot_date, quantity, average_price, exchange_rate,
        current_price, value_brl, cost_brl, created_at, updated_at, sync_status
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
      ON CONFLICT(asset_key, snapshot_date) DO UPDATE SET
        quantity = excluded.quantity,
        average_price = excluded.average_price,
        exchange_rate = excluded.exchange_rate,
        current_price = excluded.current_price,
        value_brl = excluded.value_brl,
        cost_brl = excluded.cost_brl,
        updated_at = excluded.updated_at,
        sync_status = 0
    ''', [
      asset.syncKey,
      day,
      asset.quantity,
      asset.averagePrice,
      exchangeRate,
      price,
      valueBrl,
      costBrl,
      now.toIso8601String(),
      now.toIso8601String(),
    ]);
  }

  Future<List<AssetDailySnapshot>> loadAssetDailySnapshots(
    String assetKey,
  ) async {
    final db = await database;
    final rows = await db.query(
      'asset_daily_snapshots',
      where: 'asset_key = ?',
      whereArgs: [assetKey],
      orderBy: 'snapshot_date',
    );
    return rows
        .map((row) => AssetDailySnapshot(
              assetKey: row['asset_key'] as String,
              date: DateTime.parse(row['snapshot_date'] as String),
              quantity: (row['quantity'] as num).toDouble(),
              averagePrice: (row['average_price'] as num).toDouble(),
              exchangeRate: (row['exchange_rate'] as num).toDouble(),
              currentPrice: (row['current_price'] as num).toDouble(),
              valueBrl: (row['value_brl'] as num).toDouble(),
              costBrl: (row['cost_brl'] as num).toDouble(),
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ))
        .toList();
  }

  Future<void> upsertHistory(
    InvestmentAsset asset,
    List<PricePoint> points, {
    required String source,
    bool synced = false,
  }) async {
    if (points.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final point in points) {
        batch.rawInsert('''
          INSERT INTO asset_price_history(
            asset_key, price_date, close_price, currency, source,
            created_at, updated_at, sync_status
          ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(asset_key, price_date) DO UPDATE SET
            close_price = excluded.close_price,
            currency = excluded.currency,
            source = excluded.source,
            updated_at = excluded.updated_at,
            sync_status = excluded.sync_status
          WHERE excluded.close_price != asset_price_history.close_price
             OR excluded.currency != asset_price_history.currency
             OR excluded.source != asset_price_history.source
        ''', [
          asset.syncKey,
          dateKey(point.date),
          point.value,
          asset.currency.name,
          source,
          now,
          now,
          synced ? 1 : 0,
        ]);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<PricePoint>> loadAssetHistory(
    String assetKey, {
    DateTime? from,
  }) async {
    final db = await database;
    final rows = await db.query(
      'asset_price_history',
      columns: ['price_date', 'close_price'],
      where:
          from == null ? 'asset_key = ?' : 'asset_key = ? AND price_date >= ?',
      whereArgs: from == null ? [assetKey] : [assetKey, dateKey(from)],
      orderBy: 'price_date',
    );
    return rows
        .map((row) => PricePoint(
              DateTime.parse(row['price_date'] as String),
              (row['close_price'] as num).toDouble(),
            ))
        .toList();
  }

  Future<DateTime?> newestHistoryDate(String assetKey) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT MAX(price_date) AS date FROM asset_price_history WHERE asset_key = ?',
      [assetKey],
    );
    final value = rows.first['date'] as String?;
    return value == null ? null : DateTime.parse(value);
  }

  Future<bool> historyFetchIsFresh(
    String assetKey,
    HistoryPeriod period, {
    Duration maxAge = const Duration(hours: 6),
  }) async {
    final db = await database;
    final rows = await db.query(
      'history_fetch_state',
      where: 'asset_key = ? AND period = ?',
      whereArgs: [assetKey, period.name],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final fetched = DateTime.parse(rows.first['fetched_at'] as String);
    return DateTime.now().toUtc().difference(fetched.toUtc()) < maxAge;
  }

  Future<void> markHistoryFetched(String assetKey, HistoryPeriod period) async {
    final db = await database;
    await db.insert(
      'history_fetch_state',
      {
        'asset_key': assetKey,
        'period': period.name,
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveSnapshot(double total, double cost) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final date = dateKey(now.toLocal());
    await db.rawInsert('''
      INSERT INTO portfolio_snapshots(
        snapshot_date, total_brl, cost_brl, created_at, updated_at, sync_status
      ) VALUES(?, ?, ?, ?, ?, 0)
      ON CONFLICT(snapshot_date) DO UPDATE SET
        total_brl = excluded.total_brl,
        cost_brl = excluded.cost_brl,
        updated_at = excluded.updated_at,
        sync_status = 0
    ''', [date, total, cost, now.toIso8601String(), now.toIso8601String()]);
  }

  Future<List<PortfolioSnapshot>> loadPortfolioSnapshots({
    DateTime? from,
  }) async {
    final db = await database;
    final rows = await db.query(
      'portfolio_snapshots',
      columns: ['snapshot_date', 'total_brl', 'cost_brl', 'updated_at'],
      where: from == null ? null : 'snapshot_date >= ?',
      whereArgs: from == null ? null : [dateKey(from)],
      orderBy: 'snapshot_date',
    );
    return rows
        .map((row) => PortfolioSnapshot(
              date: DateTime.parse(row['snapshot_date'] as String),
              totalBrl: (row['total_brl'] as num).toDouble(),
              costBrl: (row['cost_brl'] as num?)?.toDouble() ?? 0,
              updatedAt: DateTime.parse(
                (row['updated_at'] ?? row['snapshot_date']) as String,
              ),
            ))
        .toList();
  }

  /// Guarda as taxas diárias do CDI como publicadas, sem acumular nada.
  ///
  /// O índice é recalculado na leitura, então trocar a janela do gráfico nunca
  /// deixa dois trechos com bases diferentes.
  Future<void> upsertCdiRates(List<CdiRate> rates) async {
    if (rates.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final rate in rates) {
        batch.insert(
          'cdi_daily_rates',
          {
            'rate_date': dateKey(rate.date),
            'daily_percent': rate.dailyPercent,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<CdiRate>> loadCdiRates({DateTime? from, DateTime? to}) async {
    final db = await database;
    final conditions = <String>[
      if (from != null) 'rate_date >= ?',
      if (to != null) 'rate_date <= ?',
    ];
    final rows = await db.query(
      'cdi_daily_rates',
      columns: ['rate_date', 'daily_percent'],
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: conditions.isEmpty
          ? null
          : [
              if (from != null) dateKey(from),
              if (to != null) dateKey(to),
            ],
      orderBy: 'rate_date',
    );
    return rows
        .map((row) => CdiRate(
              date: DateTime.parse(row['rate_date'] as String),
              dailyPercent: (row['daily_percent'] as num).toDouble(),
            ))
        .toList();
  }

  /// Primeira e última data de CDI já guardadas no aparelho.
  Future<({DateTime oldest, DateTime newest})?> cdiCoverage() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT MIN(rate_date) AS oldest, MAX(rate_date) AS newest '
      'FROM cdi_daily_rates',
    );
    final oldest = rows.first['oldest'] as String?;
    final newest = rows.first['newest'] as String?;
    if (oldest == null || newest == null) return null;
    return (oldest: DateTime.parse(oldest), newest: DateTime.parse(newest));
  }

  Future<void> saveDollarQuote(MarketQuote quote) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final entry in {
        'usd_brl_current': quote.current.toString(),
        'usd_brl_previous': quote.previousClose.toString(),
        'usd_brl_updated_at': DateTime.now().toUtc().toIso8601String(),
      }.entries) {
        await txn.insert(
          'app_state',
          {'state_key': entry.key, 'state_value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<MarketQuote?> loadDollarQuote() async {
    final db = await database;
    final rows = await db.query(
      'app_state',
      where: 'state_key IN (?, ?)',
      whereArgs: ['usd_brl_current', 'usd_brl_previous'],
    );
    final values = <String, String>{
      for (final row in rows)
        row['state_key'] as String: row['state_value'] as String,
    };
    final current = double.tryParse(values['usd_brl_current'] ?? '');
    final previous = double.tryParse(values['usd_brl_previous'] ?? '');
    if (current == null) return null;
    return MarketQuote(
      current: current,
      previousClose: previous ?? current,
      history: const [],
    );
  }

  Future<List<Map<String, Object?>>> unsyncedRows(String table) async {
    final db = await database;
    return db.query(table, where: 'sync_status = 0');
  }

  Future<void> markRowsSynced(
      String table, String where, List<Object?> args) async {
    final db = await database;
    await db.update(table, {'sync_status': 1}, where: where, whereArgs: args);
  }

  Future<String?> readSyncState(String key) async {
    final db = await database;
    final rows = await db.query(
      'sync_state',
      where: 'state_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['state_value'] as String;
  }

  Future<void> writeSyncState(String key, String value) async {
    final db = await database;
    await db.insert(
      'sync_state',
      {'state_key': key, 'state_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> applyRemoteAsset(Map<String, Object?> row) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO assets(
        stable_key, symbol, name, market, currency, quantity, average_price,
        average_exchange_rate, fixed_income_kind, indexer, indexer_rate,
        application_date, maturity_date,
        created_at, updated_at, deleted_at, sync_status
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(stable_key) DO UPDATE SET
        symbol = excluded.symbol, name = excluded.name, market = excluded.market,
        currency = excluded.currency, quantity = excluded.quantity,
        average_price = excluded.average_price,
        average_exchange_rate = excluded.average_exchange_rate,
        fixed_income_kind = excluded.fixed_income_kind,
        indexer = excluded.indexer, indexer_rate = excluded.indexer_rate,
        application_date = excluded.application_date,
        maturity_date = excluded.maturity_date,
        created_at = excluded.created_at, updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at, sync_status = 1
      WHERE excluded.updated_at > assets.updated_at
    ''', [
      row['stable_key'],
      row['symbol'],
      row['name'],
      row['market'],
      row['currency'],
      row['quantity'],
      row['average_price'],
      row['average_exchange_rate'],
      row['fixed_income_kind'],
      row['indexer'],
      row['indexer_rate'],
      row['application_date'],
      row['maturity_date'],
      row['created_at'],
      row['updated_at'],
      row['deleted_at'],
    ]);
  }

  Future<void> applyRemoteHistory(Map<String, Object?> row) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO asset_price_history(
        asset_key, price_date, close_price, currency, source,
        created_at, updated_at, sync_status
      ) VALUES(?, ?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(asset_key, price_date) DO UPDATE SET
        close_price = excluded.close_price, currency = excluded.currency,
        source = excluded.source, updated_at = excluded.updated_at,
        sync_status = 1
      WHERE excluded.updated_at > asset_price_history.updated_at
    ''', [
      row['asset_key'],
      row['price_date'],
      row['close_price'],
      row['currency'],
      row['source'],
      row['created_at'],
      row['updated_at'],
    ]);
  }

  Future<void> applyRemoteSnapshot(Map<String, Object?> row) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO portfolio_snapshots(
        snapshot_date, total_brl, cost_brl, created_at, updated_at, sync_status
      ) VALUES(?, ?, ?, ?, ?, 1)
      ON CONFLICT(snapshot_date) DO UPDATE SET
        total_brl = excluded.total_brl, cost_brl = excluded.cost_brl,
        created_at = excluded.created_at, updated_at = excluded.updated_at,
        sync_status = 1
      WHERE excluded.updated_at > portfolio_snapshots.updated_at
    ''', [
      row['snapshot_date'],
      row['total_brl'],
      row['cost_brl'],
      row['created_at'],
      row['updated_at'],
    ]);
  }

  Future<void> applyRemoteTransaction(Map<String, Object?> row) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO transactions(
        id, asset_key, type, quantity, price, exchange_rate, fees, cash_value,
        transaction_date, notes, created_at, updated_at, deleted_at, sync_status
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(id) DO UPDATE SET
        asset_key = excluded.asset_key, type = excluded.type,
        quantity = excluded.quantity, price = excluded.price,
        exchange_rate = excluded.exchange_rate, fees = excluded.fees,
        cash_value = excluded.cash_value,
        transaction_date = excluded.transaction_date, notes = excluded.notes,
        updated_at = excluded.updated_at, deleted_at = excluded.deleted_at,
        sync_status = 1
      WHERE excluded.updated_at > transactions.updated_at
    ''', [
      row['id'],
      row['asset_key'],
      row['type'],
      row['quantity'],
      row['price'],
      row['exchange_rate'],
      row['fees'],
      row['cash_value'],
      row['transaction_date'],
      row['notes'],
      row['created_at'],
      row['updated_at'],
      row['deleted_at'],
    ]);
  }

  Future<void> applyRemoteAssetDailySnapshot(Map<String, Object?> row) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO asset_daily_snapshots(
        asset_key, snapshot_date, quantity, average_price, exchange_rate,
        current_price, value_brl, cost_brl, created_at, updated_at, sync_status
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(asset_key, snapshot_date) DO UPDATE SET
        quantity = excluded.quantity, average_price = excluded.average_price,
        exchange_rate = excluded.exchange_rate,
        current_price = excluded.current_price, value_brl = excluded.value_brl,
        cost_brl = excluded.cost_brl, updated_at = excluded.updated_at,
        sync_status = 1
      WHERE excluded.updated_at > asset_daily_snapshots.updated_at
    ''', [
      row['asset_key'],
      row['snapshot_date'],
      row['quantity'],
      row['average_price'],
      row['exchange_rate'],
      row['current_price'],
      row['value_brl'],
      row['cost_brl'],
      row['created_at'],
      row['updated_at'],
    ]);
  }
}

String dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

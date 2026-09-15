import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/investment_asset.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      join(root, 'openstock.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE assets(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol TEXT NOT NULL,
            name TEXT NOT NULL,
            market TEXT NOT NULL,
            currency TEXT NOT NULL,
            quantity REAL NOT NULL,
            average_price REAL NOT NULL,
            average_exchange_rate REAL NOT NULL DEFAULT 1,
            current_price REAL,
            previous_close REAL,
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX idx_assets_symbol_market
          ON assets(symbol, market)
        ''');
        await db.execute('''
          CREATE TABLE portfolio_snapshots(
            snapshot_date TEXT PRIMARY KEY,
            total_brl REAL NOT NULL,
            cost_brl REAL NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE app_state(
            state_key TEXT PRIMARY KEY,
            state_value TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<List<InvestmentAsset>> loadAssets() async {
    final db = await database;
    final rows = await db.query('assets', orderBy: 'symbol COLLATE NOCASE');
    return rows.map(InvestmentAsset.fromMap).toList();
  }

  Future<InvestmentAsset> saveAsset(InvestmentAsset asset) async {
    final db = await database;
    final values = asset.toMap()..remove('id');
    if (asset.id == null) {
      final id = await db.insert('assets', values);
      return asset.copyWith(id: id);
    }
    await db.update('assets', values, where: 'id = ?', whereArgs: [asset.id]);
    return asset;
  }

  Future<void> saveQuote(int id, MarketQuote quote) async {
    final db = await database;
    await db.update(
      'assets',
      {
        'current_price': quote.current,
        'previous_close': quote.previousClose,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAsset(int id) async {
    final db = await database;
    await db.delete('assets', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveSnapshot(double total, double cost) async {
    final db = await database;
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await db.insert(
      'portfolio_snapshots',
      {
        'snapshot_date': date,
        'total_brl': total,
        'cost_brl': cost,
        'created_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PricePoint>> loadSnapshots() async {
    final db = await database;
    final rows = await db.query(
      'portfolio_snapshots',
      orderBy: 'snapshot_date DESC',
      limit: 90,
    );
    return rows.reversed
        .map((row) => PricePoint(
              DateTime.parse(row['snapshot_date'] as String),
              (row['total_brl'] as num).toDouble(),
            ))
        .toList();
  }

  Future<void> saveDollarQuote(MarketQuote quote) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final entry in {
        'usd_brl_current': quote.current.toString(),
        'usd_brl_previous': quote.previousClose.toString(),
        'usd_brl_updated_at': DateTime.now().toIso8601String(),
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
}


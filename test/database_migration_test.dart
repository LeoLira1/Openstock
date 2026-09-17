import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/history_models.dart';
import 'package:openstock/models/investment_asset.dart';
import 'package:openstock/models/investment_transaction.dart';
import 'package:openstock/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('migração v1 preserva ativo e cria histórico sem duplicidade', () async {
    final factory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('openstock_test_');
    final path = '${directory.path}/migration.db';
    var db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
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
          await db.execute('''CREATE UNIQUE INDEX idx_assets_symbol_market
            ON assets(symbol, market)''');
          await db.execute('''CREATE TABLE portfolio_snapshots(
            snapshot_date TEXT PRIMARY KEY, total_brl REAL NOT NULL,
            cost_brl REAL NOT NULL, created_at TEXT NOT NULL)''');
          await db.execute('''CREATE TABLE app_state(
            state_key TEXT PRIMARY KEY, state_value TEXT NOT NULL)''');
        },
      ),
    );
    await db.insert('assets', {
      'symbol': 'PRIO3',
      'name': 'PRIO',
      'market': 'b3',
      'currency': 'brl',
      'quantity': 10.0,
      'average_price': 40.0,
      'average_exchange_rate': 1.0,
      'updated_at': '2026-09-15T12:00:00.000Z',
    });
    await db.close();

    db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onUpgrade: DatabaseService.migrateSchema,
      ),
    );
    final service = DatabaseService.forTesting(db);
    final assets = await service.loadAssets();
    expect(assets.single.symbol, 'PRIO3');
    expect(assets.single.syncKey, 'b3:PRIO3');

    final points = [PricePoint(DateTime(2026, 9, 15), 41)];
    await service.upsertHistory(assets.single, points, source: 'test');
    await service.upsertHistory(assets.single, points, source: 'test');
    final history = await service.loadAssetHistory('b3:PRIO3');
    expect(history, hasLength(1));
    expect(history.single.value, 41);

    // A tabela do CDI nasce na migração, sem apagar o que já existia.
    await service.upsertCdiRates([
      CdiRate(date: DateTime(2026, 9, 15), dailyPercent: 0.052531),
    ]);
    expect(await service.loadCdiRates(), hasLength(1));
    await db.close();
    await directory.delete(recursive: true);
  });

  test('sincronização local só aceita posição remota mais nova', () async {
    final directory = await Directory.systemTemp.createTemp('openstock_sync_');
    final path = '${directory.path}/sync.db';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: DatabaseService.createSchema,
      ),
    );
    final service = DatabaseService.forTesting(db);
    await service.saveAsset(const InvestmentAsset(
      stableKey: 'b3:PRIO3',
      symbol: 'PRIO3',
      name: 'PRIO',
      market: AssetMarket.b3,
      currency: AssetCurrency.brl,
      quantity: 10,
      averagePrice: 40,
    ));

    Map<String, Object?> remote(String updatedAt, double quantity) => {
          'stable_key': 'b3:PRIO3',
          'symbol': 'PRIO3',
          'name': 'PRIO remoto',
          'market': 'b3',
          'currency': 'brl',
          'quantity': quantity,
          'average_price': 42.0,
          'average_exchange_rate': 1.0,
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': updatedAt,
          'deleted_at': null,
        };

    await service.applyRemoteAsset(remote('2000-01-01T00:00:00.000Z', 1));
    expect((await service.loadAssets()).single.quantity, 10);

    await service.applyRemoteAsset(remote('2099-01-01T00:00:00.000Z', 20));
    final updated = (await service.loadAssets()).single;
    expect(updated.quantity, 20);
    expect(updated.name, 'PRIO remoto');

    await db.close();
    await directory.delete(recursive: true);
  });

  test('título de renda fixa sobrevive ao salvar e recarregar', () async {
    final directory = await Directory.systemTemp.createTemp('openstock_rf_');
    final db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/rf.db',
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: DatabaseService.createSchema,
      ),
    );
    final service = DatabaseService.forTesting(db);

    await service.saveAsset(InvestmentAsset(
      stableKey: 'fixedIncome:CDB BTG 2028',
      symbol: 'CDB BTG 2028',
      name: 'Banco BTG',
      market: AssetMarket.fixedIncome,
      currency: AssetCurrency.brl,
      quantity: 1,
      averagePrice: 5000,
      fixedIncomeKind: FixedIncomeKind.cdb,
      indexer: FixedIncomeIndexer.cdi,
      indexerRate: 110,
      applicationDate: DateTime(2026, 3, 2),
      maturityDate: DateTime(2028, 3, 2),
    ));

    final saved = (await service.loadAssets()).single;
    expect(saved.market, AssetMarket.fixedIncome);
    expect(saved.fixedIncomeKind, FixedIncomeKind.cdb);
    expect(saved.indexer, FixedIncomeIndexer.cdi);
    expect(saved.indexerRate, 110);
    expect(saved.applicationDate, DateTime(2026, 3, 2));
    expect(saved.maturityDate, DateTime(2028, 3, 2));
    expect(saved.principal, 5000);

    await db.close();
    await directory.delete(recursive: true);
  });

  test('migração v4 acrescenta as colunas de renda fixa', () async {
    final directory = await Directory.systemTemp.createTemp('openstock_v4_');
    final path = '${directory.path}/v4.db';
    var db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          // Esquema da v4: assets sem nenhuma coluna de renda fixa.
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
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deleted_at TEXT,
              sync_status INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
    await db.insert('assets', {
      'stable_key': 'b3:PRIO3',
      'symbol': 'PRIO3',
      'name': 'PRIO',
      'market': 'b3',
      'currency': 'brl',
      'quantity': 10.0,
      'average_price': 40.0,
      'average_exchange_rate': 1.0,
      'created_at': '2026-09-15T12:00:00.000Z',
      'updated_at': '2026-09-15T12:00:00.000Z',
    });
    await db.close();

    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onUpgrade: DatabaseService.migrateSchema,
      ),
    );
    final service = DatabaseService.forTesting(db);
    expect((await service.loadAssets()).single.symbol, 'PRIO3');

    final columns = await db.rawQuery('PRAGMA table_info(assets)');
    final names = columns.map((row) => row['name']).toSet();
    expect(names, containsAll(fixedIncomeColumns.keys));

    await db.close();
    await directory.delete(recursive: true);
  });

  test('CDI é guardado por dia e lido pela janela pedida', () async {
    final directory = await Directory.systemTemp.createTemp('openstock_cdi_');
    final db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/cdi.db',
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: DatabaseService.createSchema,
      ),
    );
    final service = DatabaseService.forTesting(db);

    await service.upsertCdiRates([
      CdiRate(date: DateTime(2026, 9, 14), dailyPercent: 0.05),
      CdiRate(date: DateTime(2026, 9, 15), dailyPercent: 0.05),
    ]);
    // A mesma data chega de novo na atualização incremental.
    await service.upsertCdiRates([
      CdiRate(date: DateTime(2026, 9, 15), dailyPercent: 0.06),
    ]);

    final all = await service.loadCdiRates();
    expect(all, hasLength(2));
    expect(all.last.dailyPercent, closeTo(0.06, 0.000001));

    final window = await service.loadCdiRates(from: DateTime(2026, 9, 15));
    expect(window, hasLength(1));

    final coverage = await service.cdiCoverage();
    expect(coverage?.oldest, DateTime(2026, 9, 14));
    expect(coverage?.newest, DateTime(2026, 9, 15));

    await service.saveSnapshot(1100, 1000);
    final snapshots = await service.loadPortfolioSnapshots();
    expect(snapshots.single.totalBrl, 1100);
    expect(snapshots.single.costBrl, 1000);

    await db.close();
    await directory.delete(recursive: true);
  });

  test('rastreamento cria uma única posição inicial e snapshot diário', () async {
    final directory =
        await Directory.systemTemp.createTemp('openstock_tracking_');
    final db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/tracking.db',
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: DatabaseService.createSchema,
      ),
    );
    final service = DatabaseService.forTesting(db);
    final saved = await service.saveAsset(const InvestmentAsset(
      stableKey: 'b3:PRIO3',
      symbol: 'PRIO3',
      name: 'PRIO',
      market: AssetMarket.b3,
      currency: AssetCurrency.brl,
      quantity: 100,
      averagePrice: 40,
      currentPrice: 42,
    ));

    await service.ensureOpeningTransactions([saved],
        trackingDate: DateTime(2026, 9, 17));
    await service.ensureOpeningTransactions([saved],
        trackingDate: DateTime(2026, 9, 18));
    final transactions = await service.loadTransactions();
    expect(transactions, hasLength(1));
    expect(transactions.single.type,
        InvestmentTransactionType.openingPosition);
    expect(transactions.single.transactionDate, DateTime(2026, 9, 17));

    await service.saveAssetDailySnapshot(
      saved,
      exchangeRate: 1,
      valueBrl: 4200,
      costBrl: 4000,
    );
    final snapshots = await service.loadAssetDailySnapshots(saved.syncKey);
    expect(snapshots, hasLength(1));
    expect(snapshots.single.valueBrl, 4200);

    await db.close();
    await directory.delete(recursive: true);
  });
}

import 'database_service.dart';
import 'turso_service.dart';

class SyncReport {
  const SyncReport({required this.uploaded, required this.downloaded});
  final int uploaded;
  final int downloaded;
}

class SyncService {
  SyncService(this._database, this._turso);

  final DatabaseService _database;
  final TursoService _turso;

  Future<SyncReport> synchronize() async {
    final startedAt = DateTime.now().toUtc().toIso8601String();
    await _ensureRemoteSchema();
    await _ensureRemoteFixedIncomeColumns();
    final lastSync = await _database.readSyncState('turso_last_sync') ?? '';
    var uploaded = 0;
    var downloaded = 0;

    uploaded += await _pushAssets();
    uploaded += await _pushHistory();
    uploaded += await _pushSnapshots();

    final remoteAssets = await _turso.execute(TursoStatement(
      'SELECT * FROM openstock_assets WHERE updated_at > ? ORDER BY updated_at',
      [lastSync],
    ));
    for (final row in remoteAssets) {
      await _database.applyRemoteAsset(row);
      downloaded++;
    }

    downloaded += await _pullHistory(lastSync);

    final remoteSnapshots = await _turso.execute(TursoStatement(
      'SELECT * FROM openstock_portfolio_snapshots '
      'WHERE updated_at > ? ORDER BY updated_at',
      [lastSync],
    ));
    for (final row in remoteSnapshots) {
      await _database.applyRemoteSnapshot(row);
      downloaded++;
    }

    await _database.writeSyncState('turso_last_sync', startedAt);
    return SyncReport(uploaded: uploaded, downloaded: downloaded);
  }

  Future<void> _ensureRemoteSchema() async {
    await _turso.executeBatch(const [
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS openstock_assets(
          stable_key TEXT PRIMARY KEY,
          symbol TEXT NOT NULL,
          name TEXT NOT NULL,
          market TEXT NOT NULL,
          currency TEXT NOT NULL,
          quantity REAL NOT NULL,
          average_price REAL NOT NULL,
          average_exchange_rate REAL NOT NULL,
          fixed_income_kind TEXT,
          indexer TEXT,
          indexer_rate REAL,
          application_date TEXT,
          maturity_date TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT
        )
      '''),
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS openstock_asset_price_history(
          asset_key TEXT NOT NULL,
          price_date TEXT NOT NULL,
          close_price REAL NOT NULL,
          currency TEXT NOT NULL,
          source TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY(asset_key, price_date)
        )
      '''),
      TursoStatement('''CREATE INDEX IF NOT EXISTS
        idx_openstock_history_asset_date
        ON openstock_asset_price_history(asset_key, price_date)'''),
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS openstock_portfolio_snapshots(
          snapshot_date TEXT PRIMARY KEY,
          total_brl REAL NOT NULL,
          cost_brl REAL NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      '''),
      TursoStatement('''CREATE INDEX IF NOT EXISTS idx_openstock_assets_updated
        ON openstock_assets(updated_at)'''),
      TursoStatement('''CREATE INDEX IF NOT EXISTS idx_openstock_history_updated
        ON openstock_asset_price_history(updated_at)'''),
      TursoStatement(
          '''CREATE INDEX IF NOT EXISTS idx_openstock_snapshots_updated
        ON openstock_portfolio_snapshots(updated_at)'''),
    ]);
  }

  /// Acrescenta as colunas de renda fixa em uma base remota criada antes delas.
  ///
  /// O SQLite não tem `ADD COLUMN IF NOT EXISTS`, então cada coluna vai em uma
  /// chamada isolada e a recusa por coluna já existente é o caso esperado.
  Future<void> _ensureRemoteFixedIncomeColumns() async {
    try {
      await _turso.execute(TursoStatement(
        'SELECT ${fixedIncomeColumns.keys.join(', ')} '
        'FROM openstock_assets LIMIT 1',
      ));
      return;
    } catch (_) {
      // Base remota criada antes da renda fixa: falta pelo menos uma coluna.
    }
    for (final column in fixedIncomeColumns.entries) {
      try {
        await _turso.execute(TursoStatement(
          'ALTER TABLE openstock_assets ADD COLUMN ${column.key} ${column.value}',
        ));
      } catch (_) {
        // A coluna já existe nesta base remota.
      }
    }
  }

  Future<int> _pullHistory(String lastSync) async {
    const pageSize = 1000;
    var downloaded = 0;
    String? cursorTime;
    String? cursorAsset;
    String? cursorDate;
    while (true) {
      final firstPage = cursorTime == null;
      final rows = await _turso.execute(TursoStatement(
        firstPage
            ? '''SELECT * FROM openstock_asset_price_history
                 WHERE updated_at > ?
                 ORDER BY updated_at, asset_key, price_date LIMIT $pageSize'''
            : '''SELECT * FROM openstock_asset_price_history
                 WHERE updated_at > ? AND (
                   updated_at > ? OR
                   (updated_at = ? AND asset_key > ?) OR
                   (updated_at = ? AND asset_key = ? AND price_date > ?)
                 )
                 ORDER BY updated_at, asset_key, price_date LIMIT $pageSize''',
        firstPage
            ? [lastSync]
            : [
                lastSync,
                cursorTime,
                cursorTime,
                cursorAsset,
                cursorTime,
                cursorAsset,
                cursorDate,
              ],
      ));
      for (final row in rows) {
        await _database.applyRemoteHistory(row);
        downloaded++;
      }
      if (rows.length < pageSize) break;
      final last = rows.last;
      cursorTime = last['updated_at'] as String;
      cursorAsset = last['asset_key'] as String;
      cursorDate = last['price_date'] as String;
    }
    return downloaded;
  }

  Future<int> _pushAssets() async {
    final rows = await _database.unsyncedRows('assets');
    if (rows.isEmpty) return 0;
    final statements = rows
        .map((row) => TursoStatement('''
          INSERT INTO openstock_assets(
            stable_key, symbol, name, market, currency, quantity, average_price,
            average_exchange_rate, fixed_income_kind, indexer, indexer_rate,
            application_date, maturity_date, created_at, updated_at, deleted_at
          ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(stable_key) DO UPDATE SET
            symbol=excluded.symbol, name=excluded.name, market=excluded.market,
            currency=excluded.currency, quantity=excluded.quantity,
            average_price=excluded.average_price,
            average_exchange_rate=excluded.average_exchange_rate,
            fixed_income_kind=excluded.fixed_income_kind,
            indexer=excluded.indexer, indexer_rate=excluded.indexer_rate,
            application_date=excluded.application_date,
            maturity_date=excluded.maturity_date,
            created_at=excluded.created_at, updated_at=excluded.updated_at,
            deleted_at=excluded.deleted_at
          WHERE excluded.updated_at > openstock_assets.updated_at
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
            ]))
        .toList();
    await _executeChunked(statements);
    for (final row in rows) {
      await _database
          .markRowsSynced('assets', 'stable_key = ?', [row['stable_key']]);
    }
    return rows.length;
  }

  Future<int> _pushHistory() async {
    final rows = await _database.unsyncedRows('asset_price_history');
    if (rows.isEmpty) return 0;
    final statements = rows
        .map((row) => TursoStatement('''
          INSERT INTO openstock_asset_price_history(
            asset_key, price_date, close_price, currency, source,
            created_at, updated_at
          ) VALUES(?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(asset_key, price_date) DO UPDATE SET
            close_price=excluded.close_price, currency=excluded.currency,
            source=excluded.source, updated_at=excluded.updated_at
          WHERE excluded.updated_at > openstock_asset_price_history.updated_at
        ''', [
              row['asset_key'],
              row['price_date'],
              row['close_price'],
              row['currency'],
              row['source'],
              row['created_at'],
              row['updated_at'],
            ]))
        .toList();
    await _executeChunked(statements);
    for (final row in rows) {
      await _database.markRowsSynced(
        'asset_price_history',
        'asset_key = ? AND price_date = ?',
        [row['asset_key'], row['price_date']],
      );
    }
    return rows.length;
  }

  Future<int> _pushSnapshots() async {
    final rows = await _database.unsyncedRows('portfolio_snapshots');
    if (rows.isEmpty) return 0;
    final statements = rows
        .map((row) => TursoStatement('''
          INSERT INTO openstock_portfolio_snapshots(
            snapshot_date, total_brl, cost_brl, created_at, updated_at
          ) VALUES(?, ?, ?, ?, ?)
          ON CONFLICT(snapshot_date) DO UPDATE SET
            total_brl=excluded.total_brl, cost_brl=excluded.cost_brl,
            created_at=excluded.created_at, updated_at=excluded.updated_at
          WHERE excluded.updated_at > openstock_portfolio_snapshots.updated_at
        ''', [
              row['snapshot_date'],
              row['total_brl'],
              row['cost_brl'],
              row['created_at'],
              row['updated_at'],
            ]))
        .toList();
    await _executeChunked(statements);
    for (final row in rows) {
      await _database.markRowsSynced(
          'portfolio_snapshots', 'snapshot_date = ?', [row['snapshot_date']]);
    }
    return rows.length;
  }

  Future<void> _executeChunked(List<TursoStatement> statements) async {
    const size = 100;
    for (var offset = 0; offset < statements.length; offset += size) {
      final end =
          offset + size < statements.length ? offset + size : statements.length;
      await _turso.executeBatch(statements.sublist(offset, end));
    }
  }
}

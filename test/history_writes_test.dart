import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/investment_asset.dart';
import 'package:openstock/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  const asset = InvestmentAsset(
    symbol: 'PRIO3',
    name: 'PRIO',
    market: AssetMarket.b3,
    currency: AssetCurrency.brl,
    quantity: 267,
    averagePrice: 42.38,
  );

  Future<({DatabaseService service, Database db, Directory dir})> abrir() async {
    final dir = await Directory.systemTemp.createTemp('openstock_hist_');
    final db = await databaseFactoryFfi.openDatabase(
      '${dir.path}/hist.db',
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: DatabaseService.createSchema,
      ),
    );
    return (service: DatabaseService.forTesting(db), db: db, dir: dir);
  }

  test('só o fechamento que mudou volta a ser gravado', () async {
    final ctx = await abrir();

    // Um mês de pregões, como chega em toda atualização.
    final mes = [
      for (var i = 0; i < 22; i++)
        PricePoint(DateTime(2026, 8, 20).add(Duration(days: i)), 60 + i * 0.1)
    ];

    expect(await ctx.service.upsertHistory(asset, mes, source: 'brapi'), 22);

    // A mesma série na atualização seguinte: nada mudou de valor.
    expect(await ctx.service.upsertHistory(asset, mes, source: 'brapi'), 0);

    // O pregão em curso muda de preço e um dia novo aparece.
    final seguinte = [...mes]
      ..removeLast()
      ..add(PricePoint(mes.last.date, 63.29))
      ..add(PricePoint(DateTime(2026, 9, 11), 62.74));
    expect(await ctx.service.upsertHistory(asset, seguinte, source: 'brapi'), 2);

    final historico = await ctx.service.loadAssetHistory('b3:PRIO3');
    expect(historico, hasLength(23));
    expect(historico[21].value, 63.29);
    expect(historico.last.value, 62.74);

    await ctx.db.close();
    await ctx.dir.delete(recursive: true);
  });

  test('troca de fonte reescreve o fechamento', () async {
    final ctx = await abrir();
    final pontos = [PricePoint(DateTime(2026, 9, 10), 63.29)];

    expect(await ctx.service.upsertHistory(asset, pontos, source: 'yahoo'), 1);
    expect(await ctx.service.upsertHistory(asset, pontos, source: 'yahoo'), 0);
    // O mesmo preço vindo de outra fonte precisa constar como tal.
    expect(await ctx.service.upsertHistory(asset, pontos, source: 'brapi'), 1);

    await ctx.db.close();
    await ctx.dir.delete(recursive: true);
  });

  test('série repetida não apaga o que já estava fora da janela', () async {
    final ctx = await abrir();
    await ctx.service.upsertHistory(
      asset,
      [PricePoint(DateTime(2026, 1, 15), 40.0)],
      source: 'brapi',
    );
    await ctx.service.upsertHistory(
      asset,
      [PricePoint(DateTime(2026, 9, 10), 63.29)],
      source: 'brapi',
    );

    final historico = await ctx.service.loadAssetHistory('b3:PRIO3');
    expect(historico, hasLength(2));
    expect(historico.first.value, 40.0);

    await ctx.db.close();
    await ctx.dir.delete(recursive: true);
  });
}

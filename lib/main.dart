import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'controllers/portfolio_controller.dart';
import 'models/investment_asset.dart';

const _ink = Color(0xFF0B1220);
const _surface = Color(0xFF121C2D);
const _green = Color(0xFF39E58C);
const _red = Color(0xFFFF6B78);
const _muted = Color(0xFF93A4BC);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: _ink,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: _ink,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const OpenStockApp());
}

class OpenStockApp extends StatefulWidget {
  const OpenStockApp({super.key});

  @override
  State<OpenStockApp> createState() => _OpenStockAppState();
}

class _OpenStockAppState extends State<OpenStockApp> {
  late final PortfolioController controller;

  @override
  void initState() {
    super.initState();
    controller = PortfolioController()..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _green,
      brightness: Brightness.dark,
      surface: _ink,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenStock',
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: _ink,
        useMaterial3: true,
        fontFamily: 'sans-serif',
        cardTheme: const CardThemeData(
          color: _surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            side: BorderSide(color: Color(0xFF213047)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF172338),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(15)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: PortfolioShell(controller: controller),
    );
  }
}

class PortfolioShell extends StatefulWidget {
  const PortfolioShell({super.key, required this.controller});
  final PortfolioController controller;

  @override
  State<PortfolioShell> createState() => _PortfolioShellState();
}

class _PortfolioShellState extends State<PortfolioShell> {
  var index = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: _ink,
            titleSpacing: 20,
            title: const Row(
              children: [
                _LogoMark(size: 36),
                SizedBox(width: 11),
                Text('OpenStock',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
              ],
            ),
            actions: [
              if (controller.hasForeignAssets && controller.usdBrl > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Chip(
                    avatar: const Text('US\$', style: TextStyle(fontSize: 10)),
                    label: Text(_money(controller.usdBrl, symbol: 'R\$')),
                    side: const BorderSide(color: Color(0xFF25344B)),
                    backgroundColor: _surface,
                  ),
                ),
              IconButton(
                tooltip: 'Atualizar cotações',
                onPressed: controller.refreshing ? null : controller.refresh,
                icon: controller.refreshing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: controller.loading
                ? const Center(child: CircularProgressIndicator())
                : IndexedStack(
                    index: index,
                    children: [
                      HomeDashboard(controller: controller),
                      AssetsScreen(controller: controller),
                      SettingsScreen(controller: controller),
                    ],
                  ),
          ),
          floatingActionButton: index == 2
              ? null
              : FloatingActionButton.extended(
                  backgroundColor: _green,
                  foregroundColor: _ink,
                  onPressed: () => _editAsset(context, controller),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Adicionar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
          bottomNavigationBar: NavigationBar(
            backgroundColor: const Color(0xFF0E1727),
            selectedIndex: index,
            indicatorColor: _green.withValues(alpha: .18),
            onDestinationSelected: (value) => setState(() => index = value),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard_rounded),
                  label: 'Carteira'),
              NavigationDestination(
                  icon: Icon(Icons.candlestick_chart_outlined),
                  selectedIcon: Icon(Icons.candlestick_chart_rounded),
                  label: 'Ativos'),
              NavigationDestination(
                  icon: Icon(Icons.info_outline_rounded),
                  selectedIcon: Icon(Icons.info_rounded),
                  label: 'Ajustes'),
            ],
          ),
        );
      },
    );
  }
}

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key, required this.controller});
  final PortfolioController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.assets.isEmpty) {
      return const _EmptyPortfolio();
    }
    final positive = controller.dayResult >= 0;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PATRIMÔNIO INVESTIDO',
                      style: TextStyle(
                          color: _muted, fontSize: 12, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  FittedBox(
                    child: Text(
                      _money(controller.totalValue),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ChangePill(
                        value: controller.dayResult,
                        percent: controller.dayPercent,
                      ),
                      Text(
                        'hoje',
                        style: TextStyle(color: positive ? _green : _red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 155,
                    width: double.infinity,
                    child: controller.portfolioHistory.length >= 2
                        ? PortfolioLineChart(
                            points: controller.portfolioHistory,
                            positive: controller.portfolioHistory.last.value >=
                                controller.portfolioHistory.first.value,
                          )
                        : const _ChartPlaceholder(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    controller.lastRefresh == null
                        ? 'Valores armazenados no aparelho'
                        : 'Atualizado ${DateFormat("dd/MM 'às' HH:mm").format(controller.lastRefresh!)}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (controller.message != null) ...[
            const SizedBox(height: 12),
            _Notice(text: controller.message!),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: 'Resultado total',
                  value: _signedMoney(controller.totalResult),
                  detail: _signedPercent(controller.totalPercent),
                  positive: controller.totalResult >= 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  title: 'Valor aplicado',
                  value: _money(controller.totalCost),
                  detail: '${controller.assets.length} ativos',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'Composição'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: _sortedByValue(controller)
                    .take(6)
                    .map((asset) => _AllocationRow(
                          symbol: asset.symbol,
                          value: controller.currentValue(asset),
                          ratio: controller.totalValue == 0
                              ? 0
                              : controller.currentValue(asset) /
                                  controller.totalValue,
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'Movimentos do dia'),
          const SizedBox(height: 10),
          ..._sortedByDay(controller).take(5).map(
                (asset) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _AssetSummaryTile(asset: asset, controller: controller),
                ),
              ),
        ],
      ),
    );
  }
}

class AssetsScreen extends StatelessWidget {
  const AssetsScreen({super.key, required this.controller});
  final PortfolioController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.assets.isEmpty) return const _EmptyPortfolio();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        const _SectionTitle(
          title: 'Meus ativos',
          subtitle: 'Toque em um ativo para editar',
        ),
        const SizedBox(height: 12),
        ...controller.assets.map((asset) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _editAsset(context, controller, asset),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                    child: Row(
                      children: [
                        _TickerBadge(asset: asset),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(asset.symbol,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(
                                '${_quantity(asset.quantity)} cotas • ${_marketName(asset.market)}',
                                style: const TextStyle(
                                    color: _muted, fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'PM ${_assetMoney(asset.averagePrice, asset.currency)}  •  Atual ${_assetMoney(asset.currentPrice ?? asset.averagePrice, asset.currency)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_money(controller.currentValue(asset)),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 5),
                            Text(
                              'Hoje ${_signedPercent(controller.assetDayPercent(asset))}',
                              style: TextStyle(
                                color: controller.assetDayResult(asset) >= 0
                                    ? _green
                                    : _red,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Total ${_signedPercent(controller.assetTotalPercent(asset))}',
                              style: TextStyle(
                                color: controller.assetTotalResult(asset) >= 0
                                    ? _green
                                    : _red,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              await _editAsset(context, controller, asset);
                            } else if (value == 'delete' && context.mounted) {
                              await _confirmDelete(context, controller, asset);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Editar')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Excluir', style: TextStyle(color: _red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final PortfolioController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      children: [
        const _SectionTitle(title: 'Dados e ajustes'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.key_rounded, color: _green),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Finnhub',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  _StatusChip(
                    active: controller.finnhubConfigured,
                    validated: controller.finnhubValidated,
                  ),
                ]),
                const SizedBox(height: 12),
                const Text(
                  'Fonte principal do projeto OpenStock original para ações internacionais. A chave gratuita fica protegida no armazenamento seguro do Android.',
                  style: TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 15),
                if (controller.finnhubConnectionMessage != null) ...[
                  _Notice(text: controller.finnhubConnectionMessage!),
                  const SizedBox(height: 12),
                ],
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _configureFinnhub(context, controller),
                      icon: const Icon(Icons.settings_rounded),
                      label: Text(controller.finnhubConfigured ? 'Trocar chave' : 'Configurar chave'),
                    ),
                  ),
                  if (controller.finnhubConfigured) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Testar conexão',
                      onPressed: () async {
                        final result = await controller.testFinnhub();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(result)));
                        }
                      },
                      icon: const Icon(Icons.wifi_tethering_rounded),
                    ),
                    IconButton(
                      tooltip: 'Remover chave',
                      onPressed: () => _removeFinnhub(context, controller),
                      icon: const Icon(Icons.delete_outline_rounded, color: _red),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle(title: 'Sobre o aplicativo'),
        const SizedBox(height: 12),
        Card(
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _LogoMark(size: 54),
                  SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('OpenStock',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text('Versão 1.0.0', style: TextStyle(color: _muted)),
                  ])
                ]),
                SizedBox(height: 24),
                _InfoLine(
                    icon: Icons.lock_outline_rounded,
                    title: 'Privado por padrão',
                    text: 'Sua carteira fica no banco SQLite deste aparelho.'),
                _InfoLine(
                    icon: Icons.public_rounded,
                    title: 'Mercados',
                    text: 'Finnhub para ativos internacionais, brapi.dev para B3 e consulta pública para histórico e câmbio.'),
                _InfoLine(
                    icon: Icons.schedule_rounded,
                    title: 'Atenção às cotações',
                    text: 'Os dados podem ter atraso. Fora do pregão, será exibido o último preço disponível.'),
                _InfoLine(
                    icon: Icons.balance_rounded,
                    title: 'Uso informativo',
                    text: 'O aplicativo não executa ordens nem oferece recomendação de investimento.'),
                _InfoLine(
                    icon: Icons.code_rounded,
                    title: 'Código aberto e créditos',
                    text: 'Integração baseada no Open-Dev-Society/OpenStock. Licença AGPL-3.0; código-fonte em LeoLira1/Openstock.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active, required this.validated});
  final bool active;
  final bool validated;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: (active ? _green : _muted).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(validated ? 'Conectada' : (active ? 'Salva' : 'Opcional'),
            style: TextStyle(
                color: validated ? _green : _muted,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}

class _EmptyPortfolio extends StatelessWidget {
  const _EmptyPortfolio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 120),
        child: Column(
          children: [
            const _LogoMark(size: 86),
            const SizedBox(height: 24),
            const Text('Sua carteira começa aqui',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text(
              'Cadastre sua primeira ação com a quantidade e o preço médio. O OpenStock calcula o restante em reais.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: _ink,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              ),
              onPressed: () {
                final shell = context.findAncestorStateOfType<_PortfolioShellState>();
                if (shell != null) _editAsset(context, shell.widget.controller);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar primeiro ativo'),
            ),
          ],
        ),
      ),
    );
  }
}

class AssetFormSheet extends StatefulWidget {
  const AssetFormSheet({super.key, required this.controller, this.asset});
  final PortfolioController controller;
  final InvestmentAsset? asset;

  @override
  State<AssetFormSheet> createState() => _AssetFormSheetState();
}

class _AssetFormSheetState extends State<AssetFormSheet> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController symbol;
  late final TextEditingController name;
  late final TextEditingController quantity;
  late final TextEditingController averagePrice;
  late final TextEditingController averageFx;
  late final TextEditingController currentPrice;
  late AssetMarket market;
  late AssetCurrency currency;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    symbol = TextEditingController(text: asset?.symbol ?? '');
    name = TextEditingController(text: asset?.name ?? '');
    quantity = TextEditingController(text: asset == null ? '' : _plain(asset.quantity));
    averagePrice =
        TextEditingController(text: asset == null ? '' : _plain(asset.averagePrice));
    averageFx = TextEditingController(
        text: asset == null || asset.currency == AssetCurrency.brl
            ? ''
            : _plain(asset.averageExchangeRate));
    currentPrice = TextEditingController(
        text: asset?.currentPrice == null ? '' : _plain(asset!.currentPrice!));
    market = asset?.market ?? AssetMarket.b3;
    currency = asset?.currency ?? AssetCurrency.brl;
  }

  @override
  void dispose() {
    symbol.dispose();
    name.dispose();
    quantity.dispose();
    averagePrice.dispose();
    averageFx.dispose();
    currentPrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usd = currency == AssetCurrency.usd;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .86,
        maxChildSize: .96,
        minChildSize: .55,
        builder: (context, scrollController) => Material(
          color: _ink,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Form(
            key: formKey,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF40506A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(widget.asset == null ? 'Adicionar ativo' : 'Editar ativo',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Use o código de negociação, como PRIO3 ou VOO.',
                    style: TextStyle(color: _muted)),
                const SizedBox(height: 22),
                SegmentedButton<AssetMarket>(
                  segments: const [
                    ButtonSegment(value: AssetMarket.b3, label: Text('B3')),
                    ButtonSegment(value: AssetMarket.usa, label: Text('EUA')),
                    ButtonSegment(value: AssetMarket.manual, label: Text('Manual')),
                  ],
                  selected: {market},
                  onSelectionChanged: (value) => setState(() {
                    market = value.first;
                    if (market == AssetMarket.b3) currency = AssetCurrency.brl;
                    if (market == AssetMarket.usa) currency = AssetCurrency.usd;
                  }),
                ),
                const SizedBox(height: 18),
                if (market == AssetMarket.manual) ...[
                  DropdownButtonFormField<AssetCurrency>(
                    initialValue: currency,
                    decoration: const InputDecoration(labelText: 'Moeda'),
                    items: const [
                      DropdownMenuItem(value: AssetCurrency.brl, child: Text('Real (BRL)')),
                      DropdownMenuItem(value: AssetCurrency.usd, child: Text('Dólar (USD)')),
                    ],
                    onChanged: (value) => setState(() => currency = value!),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: symbol,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Código do ativo',
                    hintText: 'Ex.: BBAS3, VOO',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe o código do ativo'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome (opcional)',
                    hintText: 'Ex.: Banco do Brasil',
                    prefixIcon: Icon(Icons.business_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _NumberField(controller: quantity, label: 'Quantidade')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      controller: averagePrice,
                      label: usd ? 'Preço médio (US\$)' : 'Preço médio (R\$)',
                    ),
                  ),
                ]),
                if (usd) ...[
                  const SizedBox(height: 14),
                  _NumberField(
                    controller: averageFx,
                    label: 'Dólar médio de compra (R\$)',
                    helper: 'Câmbio médio usado nas suas compras desse ativo.',
                  ),
                ],
                if (market == AssetMarket.manual) ...[
                  const SizedBox(height: 14),
                  _NumberField(
                    controller: currentPrice,
                    label: usd ? 'Preço atual (US\$)' : 'Preço atual (R\$)',
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: _ink,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: saving ? null : _save,
                  child: saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar ativo',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    final qty = _parseNumber(quantity.text);
    final avg = _parseNumber(averagePrice.text);
    final fx = currency == AssetCurrency.usd ? _parseNumber(averageFx.text) : 1.0;
    final current = market == AssetMarket.manual ? _parseNumber(currentPrice.text) : null;
    if (qty == null || qty <= 0 || avg == null || avg <= 0 || fx == null || fx <= 0) {
      _showError('Preencha quantidade, preço médio e câmbio com valores maiores que zero.');
      return;
    }
    if (market == AssetMarket.manual && (current == null || current <= 0)) {
      _showError('Informe o preço atual do ativo manual.');
      return;
    }
    setState(() => saving = true);
    final original = widget.asset;
    final error = await widget.controller.saveAsset(InvestmentAsset(
      id: original?.id,
      symbol: symbol.text,
      name: name.text,
      market: market,
      currency: currency,
      quantity: qty,
      averagePrice: avg,
      averageExchangeRate: fx,
      currentPrice: current ?? original?.currentPrice,
      previousClose: original?.previousClose,
      updatedAt: original?.updatedAt,
    ));
    if (!mounted) return;
    setState(() => saving = false);
    if (error != null) {
      _showError(error);
    } else {
      Navigator.pop(context);
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label, this.helper});
  final TextEditingController controller;
  final String label;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, helperText: helper),
      validator: (value) => _parseNumber(value ?? '') == null ? 'Valor inválido' : null,
    );
  }
}

class PortfolioLineChart extends StatelessWidget {
  const PortfolioLineChart({super.key, required this.points, required this.positive});
  final List<PricePoint> points;
  final bool positive;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _LineChartPainter(points, positive ? _green : _red),
      );
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.points, this.color);
  final List<PricePoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map((p) => p.value);
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(maxValue - minValue, maxValue.abs() * .01);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i / (points.length - 1) * size.width;
      final y = size.height - ((points[i].value - minValue) / range * (size.height - 10)) - 5;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: .28), color.withValues(alpha: 0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(area, areaPaint);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _green.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(size * .28),
        border: Border.all(color: _green.withValues(alpha: .35)),
      ),
      child: Icon(Icons.trending_up_rounded, color: _green, size: size * .62),
    );
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.value, required this.percent});
  final double value;
  final double percent;
  @override
  Widget build(BuildContext context) {
    final positive = value >= 0;
    final color = positive ? _green : _red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('${_signedMoney(value)}  ${_signedPercent(percent)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.detail,
    this.positive,
  });
  final String title;
  final String value;
  final String detail;
  final bool? positive;
  @override
  Widget build(BuildContext context) {
    final color = positive == null ? Colors.white : (positive! ? _green : _red);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 8),
          FittedBox(
              child: Text(value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color))),
          const SizedBox(height: 5),
          Text(detail, style: TextStyle(color: color.withValues(alpha: .8), fontSize: 12)),
        ]),
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({required this.symbol, required this.value, required this.ratio});
  final String symbol;
  final double value;
  final double ratio;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(symbol, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(_money(value), style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          SizedBox(width: 46, child: Text('${(ratio * 100).toStringAsFixed(1)}%', textAlign: TextAlign.end, style: const TextStyle(color: _muted, fontSize: 12))),
        ]),
        const SizedBox(height: 7),
        LinearProgressIndicator(
          value: ratio.clamp(0, 1),
          minHeight: 5,
          borderRadius: BorderRadius.circular(8),
          backgroundColor: const Color(0xFF25344B),
          valueColor: const AlwaysStoppedAnimation(_green),
        ),
      ]),
    );
  }
}

class _AssetSummaryTile extends StatelessWidget {
  const _AssetSummaryTile({required this.asset, required this.controller});
  final InvestmentAsset asset;
  final PortfolioController controller;
  @override
  Widget build(BuildContext context) {
    final value = controller.assetDayResult(asset);
    final positive = value >= 0;
    return Card(
      child: ListTile(
        leading: _TickerBadge(asset: asset),
        title: Text(asset.symbol, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_signedMoney(value), style: TextStyle(color: positive ? _green : _red, fontWeight: FontWeight.w700)),
          Text(_signedPercent(controller.assetDayPercent(asset)), style: TextStyle(color: positive ? _green : _red, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _TickerBadge extends StatelessWidget {
  const _TickerBadge({required this.asset});
  final InvestmentAsset asset;
  @override
  Widget build(BuildContext context) {
    final label = switch (asset.market) {
      AssetMarket.b3 => 'BR',
      AssetMarket.usa => 'US',
      AssetMarket.manual => 'M',
    };
    return Container(
      width: 43,
      height: 43,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _green.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(label, style: const TextStyle(color: _green, fontWeight: FontWeight.w800)),
    );
  }
}

class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E1727),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(22),
        child: const Text('O gráfico ganhará forma com o histórico das cotações.', textAlign: TextAlign.center, style: TextStyle(color: _muted)),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.withValues(alpha: .25)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, style: const TextStyle(color: _muted, fontSize: 12))],
      ]);
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _green, size: 22),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(color: _muted, height: 1.4)),
          ])),
        ]),
      );
}

Future<void> _editAsset(BuildContext context, PortfolioController controller,
    [InvestmentAsset? asset]) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AssetFormSheet(controller: controller, asset: asset),
  );
}

Future<void> _confirmDelete(BuildContext context, PortfolioController controller,
    InvestmentAsset asset) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Excluir ${asset.symbol}?'),
      content: const Text('O ativo será removido da carteira deste aparelho.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _red),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.deleteAsset(asset);
}

Future<void> _configureFinnhub(
    BuildContext context, PortfolioController controller) async {
  final key = TextEditingController();
  var saving = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: !saving,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Chave Finnhub'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Crie uma chave gratuita em finnhub.io e cole abaixo. Ela será validada antes de ser salva.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'API key',
                prefixIcon: Icon(Icons.key_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (key.text.trim().isEmpty) return;
                    setDialogState(() => saving = true);
                    final error = await controller.saveFinnhubKey(key.text);
                    if (!dialogContext.mounted) return;
                    if (error == null) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(controller.finnhubConnectionMessage ??
                              'Chave salva. A fonte alternativa permanece ativa.'),
                        ),
                      );
                    } else {
                      setDialogState(() => saving = false);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
            child: saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Validar e salvar'),
          ),
        ],
      ),
    ),
  );
  key.dispose();
}

Future<void> _removeFinnhub(
    BuildContext context, PortfolioController controller) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remover chave Finnhub?'),
      content: const Text(
          'Ações internacionais continuarão usando a fonte pública alternativa.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover')),
      ],
    ),
  );
  if (confirmed == true) await controller.saveFinnhubKey('');
}

List<InvestmentAsset> _sortedByValue(PortfolioController controller) =>
    [...controller.assets]
      ..sort((a, b) => controller.currentValue(b).compareTo(controller.currentValue(a)));

List<InvestmentAsset> _sortedByDay(PortfolioController controller) =>
    [...controller.assets]
      ..sort((a, b) => controller.assetDayResult(b).abs().compareTo(controller.assetDayResult(a).abs()));

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
final _usd = NumberFormat.currency(locale: 'pt_BR', symbol: 'US\$', decimalDigits: 2);

String _money(double value, {String? symbol}) => symbol == null
    ? _brl.format(value)
    : NumberFormat.currency(locale: 'pt_BR', symbol: symbol, decimalDigits: 2).format(value);
String _assetMoney(double value, AssetCurrency currency) =>
    (currency == AssetCurrency.brl ? _brl : _usd).format(value);
String _signedMoney(double value) => '${value >= 0 ? '+' : '-'}${_brl.format(value.abs())}';
String _signedPercent(double value) => '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2).replaceAll('.', ',')}%';
String _quantity(double value) => NumberFormat.decimalPattern('pt_BR').format(value);
String _plain(double value) => value.toString().replaceAll('.', ',');
String _marketName(AssetMarket market) => switch (market) {
      AssetMarket.b3 => 'B3',
      AssetMarket.usa => 'EUA',
      AssetMarket.manual => 'Manual',
    };

double? _parseNumber(String text) {
  final clean = text.trim();
  if (clean.isEmpty) return null;
  return double.tryParse(clean.contains(',')
      ? clean.replaceAll('.', '').replaceAll(',', '.')
      : clean);
}

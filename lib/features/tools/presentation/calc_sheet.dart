import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/trading_math.dart';

enum CalcType { lot, rr, margin, drawdown }

class CalcSheet extends StatefulWidget {
  const CalcSheet({required this.type, super.key});

  final CalcType type;

  @override
  State<CalcSheet> createState() => _CalcSheetState();
}

class _CalcSheetState extends State<CalcSheet> {
  final Map<String, double> _v = <String, double>{
    'balance': 10000,
    'risk': 1,
    'stop': 20,
    'entry': 2345.50,
    'target': 2366.50,
    'price': 2345.50,
    'leverage': 100,
    'lots': 1,
    'budget': 500,
  };
  String _symbol = 'XAUUSD';
  String _title = '';

  @override
  Widget build(BuildContext context) {
    _title = switch (widget.type) {
      CalcType.lot => 'Lot Size',
      CalcType.rr => 'Risk / Reward',
      CalcType.margin => 'Margin',
      CalcType.drawdown => 'Drawdown Sim',
    };

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_title, style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text(_resultText(), style: AppTextStyles.h1.copyWith(color: AppColors.primary)),
            const SizedBox(height: 16),
            if (widget.type != CalcType.margin)
              _symbolField(),
            ..._fields(),
            const SizedBox(height: 8),
            const Text(
              'Illustrative only. Verify contract specs and pip values with your broker.',
              style: AppTextStyles.disclaimer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _symbolField() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: _symbol,
          dropdownColor: AppColors.surfaceAlt,
          decoration: const InputDecoration(labelText: 'Symbol'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(value: 'XAUUSD', child: Text('XAUUSD (Gold)')),
            DropdownMenuItem<String>(value: 'EURUSD', child: Text('EURUSD')),
            DropdownMenuItem<String>(value: 'GBPUSD', child: Text('GBPUSD')),
            DropdownMenuItem<String>(value: 'USDJPY', child: Text('USDJPY')),
            DropdownMenuItem<String>(value: 'XAGUSD', child: Text('XAGUSD (Silver)')),
          ],
          onChanged: (String? v) => setState(() => _symbol = v ?? _symbol),
        ),
      );

  List<Widget> _fields() {
    final List<Widget> out = <Widget>[];
    void field(String key, String label) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            initialValue: _v[key]!.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label),
            style: AppTextStyles.body,
            onChanged: (String s) {
              final double? d = double.tryParse(s);
              if (d != null) setState(() => _v[key] = d);
            },
          ),
        ),
      );
    }

    switch (widget.type) {
      case CalcType.lot:
        field('balance', 'Account Balance (\$)');
        field('risk', 'Risk (%)');
        field('stop', 'Stop Loss (pips)');
      case CalcType.rr:
        field('entry', 'Entry');
        field('stop', 'Stop Loss');
        field('target', 'Target');
      case CalcType.margin:
        field('lots', 'Lots');
        field('price', 'Price');
        field('leverage', 'Leverage (1:x)');
      case CalcType.drawdown:
        field('budget', 'Drawdown Budget (\$)');
        field('stop', 'Stop Loss (pips)');
    }
    return out;
  }

  String _resultText() {
    switch (widget.type) {
      case CalcType.lot:
        final double lots = TradingMath.lotSize(
          balance: _v['balance']!,
          riskPct: _v['risk']!,
          symbol: _symbol,
          stopPips: _v['stop']!,
        );
        return '$lots lots  /  '
            '${Formatters.money(_v['balance']! * _v['risk']! / 100)} risk';
      case CalcType.rr:
        final double rr = TradingMath.rewardRisk(
          entry: _v['entry']!,
          stop: _v['stop']!,
          target: _v['target']!,
        );
        return '1 : ${rr.toStringAsFixed(2)}';
      case CalcType.margin:
        final double m = TradingMath.marginRequired(
          lots: _v['lots']!,
          price: _v['price']!,
          leverage: _v['leverage']!,
          symbol: _symbol,
        );
        return Formatters.money(m);
      case CalcType.drawdown:
        final double lots = TradingMath.safeLotsForDrawdown(
          drawdownBudget: _v['budget']!,
          symbol: _symbol,
          stopPips: _v['stop']!,
        );
        return '$lots max lots';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/account.dart';
import '../../../core/models/copy_settings.dart';
import '../../../core/models/signal.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/trading_math.dart';
import '../../../core/widgets/disclaimer_note.dart';
import '../domain/copy_preview.dart';

/// S8 — the copy confirm bottom sheet (task 3.4).
///
/// Signal summary, account picker, risk slider (0.25–5.0%, default 1%),
/// per-account lots / pip value / max-loss preview, paper-mode pill,
/// confirm → result toast, verbatim risk disclaimer.
///
/// Every number comes from [CopyPreview.of] / [TradingMath] — the same
/// formula the `copy-signal` Edge Function applies server-side (the parity
/// fixtures are duplicated verbatim in `test/copy_policy_test.dart`, so the
/// two sides cannot drift apart silently). The sheet never authorizes
/// anything: it shows what WOULD be placed, and the server recomputes from
/// live equity and re-runs every guardrail before anything is ordered.
///
/// Selection is local state, deliberately NOT `selectedAccountIdProvider`:
/// picking a copy target must not move the Guard screen's account
/// underneath the trader. It is only seeded from that provider once.
class CopyConfirmSheet extends StatefulWidget {
  const CopyConfirmSheet({required this.signal, super.key});

  final Signal signal;

  @override
  State<CopyConfirmSheet> createState() => _CopyConfirmSheetState();
}

class _CopyConfirmSheetState extends State<CopyConfirmSheet> {
  /// Band and default from [CopySettings] — identical to the server's
  /// `MIN_RISK_PCT` / `MAX_RISK_PCT` / `DEFAULT_RISK_PCT`, so a preview this
  /// sheet accepted can never be resized by the server's clamp.
  double _riskPct = CopySettings.defaultRiskPct;

  /// Accounts to copy into, seeded once from the Guard screen's selection.
  final Set<String> _selectedIds = <String>{};
  bool _selectionSeeded = false;

  double get _stopPips => TradingMath.pipsBetween(
        widget.signal.pair,
        widget.signal.entry,
        widget.signal.stop,
      );

  double get _rewardRisk => TradingMath.rewardRisk(
        entry: widget.signal.entry,
        stop: widget.signal.stop,
        target: widget.signal.tp1,
      );

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final List<TradingAccount> accounts = ref.watch(accountsProvider);
        if (accounts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Connect a broker account first.',
                style: AppTextStyles.body,
              ),
            ),
          );
        }

        if (!_selectionSeeded) {
          _selectionSeeded = true;
          _selectedIds.add(
            ref.read(selectedAccountProvider)?.id ?? accounts.first.id,
          );
        }
        // An account removed while the sheet is open must not leave a
        // dangling selection whose preview cannot be resolved below.
        _selectedIds.retainAll(accounts.map((TradingAccount a) => a.id));

        final Map<String, CopyPreview> previews = <String, CopyPreview>{
          for (final TradingAccount a in accounts)
            a.id: CopyPreview.of(
              signal: widget.signal,
              account: a,
              riskPct: _riskPct,
            ),
        };
        final List<CopyPreview> placeable = <CopyPreview>[
          for (final String id in _selectedIds)
            if (previews[id]!.isPlaceable) previews[id]!,
        ];

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
                Row(
                  children: <Widget>[
                    const Text('Copy Signal', style: AppTextStyles.h2),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'PAPER MODE',
                        style:
                            AppTextStyles.label.copyWith(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${widget.signal.pair} • '
                  '${widget.signal.direction == SignalDirection.buy ? 'BUY' : 'SELL'}'
                  ' • ${_stopPips.toStringAsFixed(1)} pips SL'
                  ' • 1:${_rewardRisk.toStringAsFixed(2)}',
                  style: AppTextStyles.body,
                ),
                Text(
                  'Entry ${_level(widget.signal.entry)}'
                  ' · SL ${_level(widget.signal.stop)}'
                  ' · TP ${_level(widget.signal.tp1)}',
                  style: AppTextStyles.muted,
                ),
                const SizedBox(height: 16),
                Text(
                  'Risk: ${_riskPct.toStringAsFixed(2)}%',
                  style: AppTextStyles.body,
                ),
                Slider(
                  value: _riskPct,
                  min: CopySettings.minRiskPct,
                  max: CopySettings.maxRiskPct,
                  divisions:
                      ((CopySettings.maxRiskPct - CopySettings.minRiskPct) /
                              0.25)
                          .round(),
                  activeColor: AppColors.primary,
                  onChanged: (double v) => setState(() => _riskPct = v),
                ),
                _row(
                  'Pip value',
                  '${Formatters.money(TradingMath.pipValue(widget.signal.pair))} per pip',
                ),
                const SizedBox(height: 12),
                Text(
                  'ACCOUNTS — ${_selectedIds.length} of ${accounts.length}'
                  ' selected (max ${CopySettings.maxAccountsPerRequest})',
                  style: AppTextStyles.label,
                ),
                for (final TradingAccount a in accounts)
                  _accountRow(a, previews[a.id]!),
                if (_selectedIds.isEmpty)
                  const Text(
                    'Select at least one account to copy.',
                    style: AppTextStyles.muted,
                  )
                else if (placeable.isEmpty)
                  Text(
                    'Selected accounts cannot be copied at this size — see '
                    'the reasons above.',
                    style:
                        AppTextStyles.muted.copyWith(color: AppColors.danger),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Preview only — the server recomputes lots from live equity '
                  'and re-checks kill switch, consent, per-account permission '
                  'and caps before placing.',
                  style: AppTextStyles.disclaimer,
                ),
                const SizedBox(height: 12),
                const DisclaimerNote(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedIds.isEmpty || placeable.isEmpty
                        ? null
                        : () => _confirm(context, placeable, accounts),
                    child: const Text('Confirm Copy'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Sheet rows use a compact level format: gold-style prices keep 2dp,
  /// FX-style prices keep 4dp — same rule as [SignalCard], so a price reads
  /// identically on the card and in the sheet.
  String _level(double v) => v >= 100 ? v.toStringAsFixed(2) : v.toStringAsFixed(4);

  /// One picker row: identity + equity on the left, the computed size and
  /// its loss at the stop on the right, the refusal reason (if any) below.
  /// Rows are previewed whether checked or not, so the trader can compare
  /// sizes across accounts before choosing.
  Widget _accountRow(TradingAccount account, CopyPreview preview) {
    return CheckboxListTile(
      value: _selectedIds.contains(account.id),
      onChanged: (bool? checked) => _toggle(account.id, checked),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(account.nickname, style: AppTextStyles.body),
                Text(
                  '${Formatters.money(account.equity)} equity',
                  style: AppTextStyles.muted,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${preview.lots.toStringAsFixed(2)} lots',
                style: AppTextStyles.body,
              ),
              Text(
                'max loss ${Formatters.money(preview.maxLoss)}',
                style: AppTextStyles.muted,
              ),
            ],
          ),
        ],
      ),
      subtitle: preview.refusal == null
          ? null
          : Text(
              _refusalText(preview),
              style: AppTextStyles.muted.copyWith(color: AppColors.danger),
            ),
    );
  }

  void _toggle(String accountId, bool? checked) {
    if (checked == null) return;
    if (checked &&
        !_selectedIds.contains(accountId) &&
        _selectedIds.length >= CopySettings.maxAccountsPerRequest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Up to ${CopySettings.maxAccountsPerRequest} accounts per copy.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (checked) {
        _selectedIds.add(accountId);
      } else {
        _selectedIds.remove(accountId);
      }
    });
  }

  /// The refused size is part of the message on purpose: `maxLots` reports
  /// the exact lots the server also reports, so the trader reads WHY rather
  /// than a bare failure — a size the trader never reviewed is exactly the
  /// thing the cap exists to prevent.
  String _refusalText(CopyPreview preview) => switch (preview.refusal!) {
        CopyRefusal.inactiveSignal =>
          'Signal is closed — only active signals can be copied.',
        CopyRefusal.invalidSignal =>
          'Stop distance is zero — this signal cannot be sized.',
        CopyRefusal.maxLots =>
          '${preview.lots.toStringAsFixed(2)} lots is over the '
              '${CopySettings.defaultMaxLots.toStringAsFixed(2)}-lot cap — '
              'reduce risk to copy this account.',
      };

  void _confirm(
    BuildContext context,
    List<CopyPreview> placeable,
    List<TradingAccount> accounts,
  ) {
    final Map<String, TradingAccount> byId = <String, TradingAccount>{
      for (final TradingAccount a in accounts) a.id: a,
    };
    final String summary = placeable
        .map(
          (CopyPreview p) =>
              '${byId[p.accountId]!.nickname} ${p.lots.toStringAsFixed(2)} lots',
        )
        .join(', ');
    // Grab the messenger BEFORE the pop: the sheet's element is gone on the
    // next frame, and resolving an inherited widget from a disposed context
    // is the kind of bug that only shows up in release builds.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Paper copy simulated: $summary. Nothing sent to a broker.'),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: AppTextStyles.muted),
            Text(value, style: AppTextStyles.body),
          ],
        ),
      );
  }


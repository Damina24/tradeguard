import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/account.dart';
import '../../../core/services/broker_connect_service.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/disclaimer_note.dart';

/// Broker connect sheet. Reached from Settings → "Connect broker (read-only)".
///
/// The password field is cleared from the controllers as soon as the request completes, and is
/// never copied into [ConnectState], so it cannot outlive the call. TradeGuard stores only the
/// returned `metaapi_account_id` — broker credentials are never persisted.
Future<bool> showConnectBrokerSheet(BuildContext context) async {
  final bool? connected = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => const ConnectBrokerSheet(),
  );
  return connected ?? false;
}

class ConnectBrokerSheet extends ConsumerStatefulWidget {
  const ConnectBrokerSheet({super.key});

  @override
  ConsumerState<ConnectBrokerSheet> createState() => _ConnectBrokerSheetState();
}

class _ConnectBrokerSheetState extends ConsumerState<ConnectBrokerSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nickname = TextEditingController();
  final TextEditingController _login = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _server = TextEditingController();
  final TextEditingController _propFirm = TextEditingController();
  final TextEditingController _initialBalance = TextEditingController(text: '100000');
  final TextEditingController _profitTarget = TextEditingController(text: '8000');
  final TextEditingController _dailyLoss = TextEditingController(text: '5000');
  final TextEditingController _maxDrawdown = TextEditingController(text: '10000');

  String _platform = BrokerConnectionRequest.platforms.first;
  AccountPhase _phase = AccountPhase.eval;
  DrawdownType _drawdownType = DrawdownType.trailing;
  bool _obscure = true;
  bool _enableGuard = true;

  @override
  void dispose() {
    _nickname.dispose();
    _login.dispose();
    _password.dispose();
    _server.dispose();
    _propFirm.dispose();
    _initialBalance.dispose();
    _profitTarget.dispose();
    _dailyLoss.dispose();
    _maxDrawdown.dispose();
    super.dispose();
  }

  double? _number(TextEditingController c) => double.tryParse(c.text.trim());

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final BrokerConnectionRequest request = BrokerConnectionRequest(
      login: _login.text.trim(),
      password: _password.text,
      server: _server.text.trim(),
      platform: _platform,
      nickname: _nickname.text,
      phase: _phase,
      currency: 'USD',
      initialBalance: _number(_initialBalance) ?? 0,
      profitTarget: _number(_profitTarget) ?? 0,
      dailyLossLimit: _number(_dailyLoss) ?? 0,
      maxDrawdown: _number(_maxDrawdown) ?? 0,
      drawdownType: _drawdownType,
      propFirm: _propFirm.text.trim().isEmpty ? null : _propFirm.text.trim(),
      enableEquityGuard: _enableGuard,
    );

    final ConnectAccountNotifier notifier =
        ref.read(connectAccountProvider.notifier);
    final String? id = await notifier.connect(request);

    // Drop the secret from memory the moment the call is done, successful or not.
    _password.clear();

    if (!mounted) return;
    if (id == null) {
      setState(() {}); // surfaces notifier.state.message
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ConnectState state = ref.watch(connectAccountProvider);
    final bool stubbed = ref.read(connectAccountProvider.notifier).isStubbed;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text('Connect broker', style: AppTextStyles.h2),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                ),
              ],
            ),
            const Text(
              'Read-only. We only read equity and balance — TradeGuard never places '
              'orders from this screen.',
              style: AppTextStyles.muted,
            ),
            const SizedBox(height: 16),
            const _Label('BROKER CREDENTIALS'),
            _Field(
              controller: _login,
              label: 'Account number',
              hint: 'e.g. 5012345',
              keyboardType: TextInputType.number,
              formatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            _Field(
              controller: _password,
              label: 'Password',
              obscure: _obscure,
              suffix: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                // Show the "reveal" affordance only while the password is actually hidden.
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            _Field(
              controller: _server,
              label: 'Server',
              hint: 'e.g. FTMO-Demo',
            ),
            const SizedBox(height: 8),
            _Dropdown<String>(
              label: 'PLATFORM',
              value: _platform,
              items: BrokerConnectionRequest.platforms,
              labels: BrokerConnectionRequest.platforms
                  .map((String p) => p.toUpperCase())
                  .toList(),
              onChanged: (String? v) =>
                  setState(() => _platform = v ?? _platform),
            ),
            const SizedBox(height: 16),
            const _Label('PROP RULES'),
            _Field(controller: _nickname, label: 'Nickname'),
            _Field(controller: _propFirm, label: 'Prop firm (optional)'),
            _Dropdown<AccountPhase>(
              label: 'PHASE',
              value: _phase,
              items: AccountPhase.values,
              labels: AccountPhase.values
                  .map((AccountPhase p) => p.label)
                  .toList(),
              onChanged: (AccountPhase? v) =>
                  setState(() => _phase = v ?? _phase),
            ),
            _Field(
              controller: _initialBalance,
              label: 'Initial balance',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              formatters: <TextInputFormatter>[_decimalOnly],
            ),
            _Field(
              controller: _profitTarget,
              label: 'Profit target',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              formatters: <TextInputFormatter>[_decimalOnly],
            ),
            _Field(
              controller: _dailyLoss,
              label: 'Daily loss limit',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              formatters: <TextInputFormatter>[_decimalOnly],
            ),
            _Field(
              controller: _maxDrawdown,
              label: 'Max drawdown',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              formatters: <TextInputFormatter>[_decimalOnly],
            ),
            _Dropdown<DrawdownType>(
              label: 'DRAWDOWN TYPE',
              value: _drawdownType,
              items: DrawdownType.values,
              labels: const <String>['Static', 'Trailing'],
              onChanged: (DrawdownType? v) =>
                  setState(() => _drawdownType = v ?? _drawdownType),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enableGuard,
              onChanged: (bool v) => setState(() => _enableGuard = v),
              title:
                  const Text('Enable equity guard', style: AppTextStyles.body),
              subtitle: const Text(
                'Alerts at 70% and 90% of the daily loss limit.',
                style: AppTextStyles.muted,
              ),
            ),
            if (state.status == ConnectStatus.failure &&
                state.message != null) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.message!,
                        style: AppTextStyles.muted
                            .copyWith(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: state.isBusy ? null : _submit,
                child: state.isBusy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect account'),
              ),
            ),
            if (stubbed) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'Demo mode — no broker is contacted and no account id is real.',
                style: AppTextStyles.disclaimer,
              ),
            ],
            const SizedBox(height: 12),
            const DisclaimerNote(
              text: 'Your broker password is relayed to our secure connect service '
                  'and immediately discarded. TradeGuard stores only the account '
                  'identifier — never your credentials.',
            ),
          ],
        ),
      ),
    );
  }
}


/// Allows digits plus decimal separators, so a money field can't silently become NaN.
final TextInputFormatter _decimalOnly =
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: AppTextStyles.label),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
    this.formatters,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        autocorrect: false,
        enableSuggestions: !obscure,
        style: AppTextStyles.body,
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceAlt,
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// Small generic dropdown so the platform / phase / drawdown pickers stay visually identical.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labels,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final List<String> labels;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: AppColors.surfaceAlt,
        style: AppTextStyles.body,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceAlt,
          border: const OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<T>>[
          for (int i = 0; i < items.length; i++)
            DropdownMenuItem<T>(
              value: items[i],
              child: Text(labels[i], style: AppTextStyles.body),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

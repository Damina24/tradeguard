enum AccountPhase { eval, funded, personal }

enum DrawdownType { static, trailing }

extension AccountPhaseX on AccountPhase {
  String get label => switch (this) {
        AccountPhase.eval => 'EVAL',
        AccountPhase.funded => 'FUNDED',
        AccountPhase.personal => 'PERSONAL',
      };
}

class TradingAccount {
  const TradingAccount({
    required this.id,
    required this.nickname,
    required this.platform,
    required this.phase,
    required this.currency,
    required this.initialBalance,
    required this.profitTarget,
    required this.dailyLossLimit,
    required this.maxDrawdown,
    required this.drawdownType,
    required this.equity,
    required this.balance,
    required this.dailyPnl,
    required this.peakEquity,
    this.propFirm,
    this.metaapiAccountId,
    this.equityGuardEnabled = false,
    this.copyEnabled = false,
  });

  final String id;
  final String nickname;
  final String platform; // mt4 | mt5 | ctrader
  final AccountPhase phase;
  final String currency;
  final double initialBalance;
  final double profitTarget;
  final double dailyLossLimit;
  final double maxDrawdown;
  final DrawdownType drawdownType;
  final double equity;
  final double balance;
  final double dailyPnl;
  final double peakEquity;
  final String? propFirm;

  /// Opaque MetaAPI account id. Broker credentials are NEVER stored client- or server-side — only
  /// this id travels, and every broker call is proxied through an Edge Function.
  final String? metaapiAccountId;
  final bool equityGuardEnabled;

  /// Per-account copy permission (`broker_accounts.copy_enabled`, migration
  /// 0009). OFF by default — exactly the column default — so a freshly
  /// connected account refuses every follow (`accountDisabled`) until the
  /// trader turns it on in Settings. The server re-reads this column on every
  /// request; the client holds it only so the preview can say why before the
  /// round trip.
  final bool copyEnabled;

  factory TradingAccount.fromJson(Map<String, dynamic> json) => TradingAccount(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        platform: json['platform'] as String? ?? 'mt5',
        phase: AccountPhase.values.firstWhere(
          (AccountPhase p) => p.name == (json['phase'] ?? 'eval'),
          orElse: () => AccountPhase.eval,
        ),
        currency: json['currency'] as String? ?? 'USD',
        initialBalance: (json['initial_balance'] as num?)?.toDouble() ?? 0,
        profitTarget: (json['profit_target'] as num?)?.toDouble() ?? 0,
        dailyLossLimit: (json['daily_loss_limit'] as num?)?.toDouble() ?? 0,
        maxDrawdown: (json['max_drawdown'] as num?)?.toDouble() ?? 0,
        drawdownType: (json['drawdown_type'] == 'trailing')
            ? DrawdownType.trailing
            : DrawdownType.static,
        equity: (json['equity'] as num?)?.toDouble() ?? 0,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        dailyPnl: (json['daily_pnl'] as num?)?.toDouble() ?? 0,
        peakEquity: (json['peak_equity'] as num?)?.toDouble() ?? 0,
        propFirm: json['prop_firm'] as String?,
        metaapiAccountId: json['metaapi_account_id'] as String?,
        equityGuardEnabled: json['equity_guard_enabled'] as bool? ?? false,
        copyEnabled: json['copy_enabled'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'nickname': nickname,
        'platform': platform,
        'phase': phase.name,
        'currency': currency,
        'initial_balance': initialBalance,
        'profit_target': profitTarget,
        'daily_loss_limit': dailyLossLimit,
        'max_drawdown': maxDrawdown,
        'drawdown_type': drawdownType.name,
        'equity': equity,
        'balance': balance,
        'daily_pnl': dailyPnl,
        'peak_equity': peakEquity,
        'prop_firm': propFirm,
        'metaapi_account_id': metaapiAccountId,
        'equity_guard_enabled': equityGuardEnabled,
        'copy_enabled': copyEnabled,
      };
}

import 'package:flutter/material.dart';
import 'package:trufi_core_ui/trufi_core_ui.dart';

import 'auth_gate.dart';

/// Pantalla "Mi cuenta" del menu lateral. Tiene su propio AppBar porque
/// AuthGate ya muestra un Scaffold completo con el estado de la sesion.
class AccountTrufiScreen extends TrufiScreen {
  @override
  String get id => 'account';

  @override
  String get path => '/account';

  @override
  Widget Function(BuildContext context) get builder => (_) => const AuthGate();

  @override
  ScreenMenuItem? get menuItem => const ScreenMenuItem(
        icon: Icons.account_circle_rounded,
        order: 5,
        showDividerBefore: true,
      );

  @override
  List<LocalizationsDelegate> get localizationsDelegates => const [];

  @override
  bool get hasOwnAppBar => true;

  @override
  String getLocalizedTitle(BuildContext context) => 'Mi cuenta';
}

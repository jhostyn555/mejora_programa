import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'login_screen.dart';
import 'role_home.dart';
import 'supabase_config.dart';

/// Decide la pantalla segun la sesion. Cada cambio de sesion (entrar o salir)
/// vuelve a construir esta pantalla, asi que el boton de salir siempre
/// lleva al inicio sin depender de la navegacion.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Si se detectó la service_role key, no inicializamos Supabase y
    // mostramos el aviso aquí.
    if (supabaseInitWarning != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mi cuenta')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              supabaseInitWarning!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      );
    }
    final auth = AuthService();
    return StreamBuilder<AuthState>(
      stream: auth.authChanges,
      builder: (context, _) {
        return auth.isSignedIn ? const RoleHome() : const LoggedOutPage();
      },
    );
  }
}

class LoggedOutPage extends StatelessWidget {
  const LoggedOutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.directions_bus_rounded, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Inicia sesión para ver tu cuenta, solicitar roles y '
                'acceder al panel administrativo.',
                textAlign: TextAlign.center,
              ),
              if (!isSupabaseConfigured) ...[
                const SizedBox(height: 12),
                Text(
                  supabaseMissingConfigMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Iniciar sesión'),
                onPressed: () => showLoginDialog(context),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Crear cuenta'),
                onPressed: () =>
                    showLoginDialog(context, registering: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

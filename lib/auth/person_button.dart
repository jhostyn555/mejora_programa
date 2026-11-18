import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'login_screen.dart';
import 'role_home.dart';
import 'supabase_config.dart';

/// Boton de persona: sin sesion abre el formulario flotante de login;
/// con sesion abre el panel de la cuenta.
class PersonButton extends StatelessWidget {
  const PersonButton({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return StreamBuilder<AuthState>(
      stream: auth.authChanges,
      builder: (context, _) {
        final signedIn = auth.isSignedIn;
        return IconButton(
          tooltip: signedIn ? 'Mi cuenta' : 'Iniciar sesión',
          icon: Icon(signedIn ? Icons.account_circle : Icons.person_outline),
          onPressed: () {
            if (signedIn) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RoleHome()),
              );
            } else {
              showLoginDialog(context);
            }
          },
        );
      },
    );
  }
}

/// Botones de cuenta en el pie del menu lateral (vista de usuario).
/// Sin sesion ofrece 'Iniciar sesion' y 'Crear cuenta'; con sesion ofrece
/// 'Mi cuenta' y 'Cerrar sesion'.
class AuthDrawerFooter extends StatelessWidget {
  const AuthDrawerFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return StreamBuilder<AuthState>(
      stream: auth.authChanges,
      builder: (context, _) {
        final signedIn = auth.isSignedIn;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (supabaseInitWarning != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  supabaseInitWarning!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              )
            else if (!isSupabaseConfigured)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Inicia sesión no disponible: falta configurar Supabase.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            FilledButton.icon(
              icon: Icon(signedIn ? Icons.account_circle : Icons.login),
              label: Text(signedIn ? 'Mi cuenta' : 'Iniciar sesión'),
              onPressed: () {
                if (signedIn) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RoleHome()),
                  );
                } else {
                  showLoginDialog(context);
                }
              },
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              icon: Icon(
                signedIn ? Icons.logout : Icons.person_add_alt_1,
              ),
              label: Text(signedIn ? 'Cerrar sesión' : 'Crear cuenta'),
              onPressed: signedIn
                  ? () async {
                      await auth.signOut();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sesión cerrada'),
                          ),
                        );
                      }
                    }
                  : () => showLoginDialog(context, registering: true),
            ),
          ],
        );
      },
    );
  }
}

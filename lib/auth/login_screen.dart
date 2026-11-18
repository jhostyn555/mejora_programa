import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'supabase_config.dart';

/// Abre el formulario flotante de inicio de sesion y registro.
/// Devuelve true si la sesion se inicio correctamente.
Future<bool?> showLoginDialog(
  BuildContext context, {
  bool registering = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => LoginDialog(initiallyRegistering: registering),
  );
}

class LoginDialog extends StatefulWidget {
  final bool initiallyRegistering;

  const LoginDialog({super.key, this.initiallyRegistering = false});

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _auth = AuthService();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  late bool _registering = widget.initiallyRegistering;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_registering && _name.text.trim().isEmpty) {
      return 'Escribe tu nombre.';
    }
    final email = _email.text.trim();
    if (email.isEmpty) return 'Escribe tu correo.';
    if (!email.contains('@') || !email.contains('.')) {
      return 'Escribe un correo valido.';
    }
    if (_password.text.isEmpty) return 'Escribe tu contrasena.';
    if (_password.text.length < 6) {
      return 'La contrasena debe tener al menos 6 caracteres.';
    }
    return null;
  }

  Future<void> _submit() async {
    final validation = _validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final email = _email.text.trim();
      final password = _password.text;
      if (_registering) {
        await _auth.signUp(
          email: email,
          password: password,
          fullName: _name.text.trim(),
        );
        // Si Supabase exige confirmar el correo, no hay sesion todavia.
        if (_auth.currentUser == null) {
          if (mounted) {
            setState(() => _info = 'Revisa tu correo para confirmar la cuenta.');
          }
          return;
        }
      } else {
        await _auth.signIn(email, password);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo iniciar sesion: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _registering ? 'Crear cuenta' : 'Iniciar sesión',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close),
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                if (!isSupabaseConfigured) ...[
                  const SizedBox(height: 8),
                  Text(
                    supabaseMissingConfigMessage,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                if (_registering) ...[
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  Text(_info!),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_registering ? 'Registrarme' : 'Entrar'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _registering = !_registering;
                            _error = null;
                            _info = null;
                          }),
                  child: Text(
                    _registering
                        ? 'Ya tengo cuenta'
                        : 'No tengo cuenta, quiero registrarme',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

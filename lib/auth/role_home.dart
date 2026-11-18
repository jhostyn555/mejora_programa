import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'views.dart';

/// Panel de la cuenta: muestra la vista segun el rol confirmado en la base.
class RoleHome extends StatefulWidget {
  const RoleHome({super.key});

  @override
  State<RoleHome> createState() => _RoleHomeState();
}

class _RoleHomeState extends State<RoleHome> {
  final _auth = AuthService();
  late Future<Profile?> _profile = _auth.fetchProfile();

  void _reload() => setState(() => _profile = _auth.fetchProfile());

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    // Si se abrio desde otra pantalla, vuelve a ella. Si esta en la raiz,
    // AuthGate se reconstruye solo al cerrar la sesion.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi cuenta'),
        actions: [
          TextButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<Profile?>(
        future: _profile,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final profile = snap.data;
          if (profile == null) {
            return const Center(child: Text('No hay sesión activa'));
          }

          final view = switch (profile.role) {
            AppRole.cliente || AppRole.admin =>
              ClienteView(profile: profile, onChanged: _reload),
            AppRole.transportista => const TransportistaView(),
            AppRole.control => const ControlView(),
          };

          return Column(
            children: [
              if (profile.requestedRole != null)
                Container(
                  width: double.infinity,
                  color: Colors.amber.shade100,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Solicitud de rol "${profile.requestedRole!.name}" pendiente de aprobación.',
                  ),
                ),
              Expanded(child: view),
            ],
          );
        },
      ),
    );
  }
}
import 'package:flutter/material.dart';

import 'auth_service.dart';

String _roleLabel(AppRole role) => switch (role) {
      AppRole.cliente => 'Cliente',
      AppRole.transportista => 'Transportista',
      AppRole.control => 'Control de líneas',
      AppRole.admin => 'Administrador',
    };

/// Menu del cliente. Si la cuenta es administradora, muestra dos paneles:
/// el panel de cliente y un panel con el boton para entrar al panel admin.
class ClienteView extends StatelessWidget {
  final Profile profile;
  final VoidCallback onChanged;

  const ClienteView({super.key, required this.profile, required this.onChanged});

  Future<void> _request(BuildContext context, AppRole role) async {
    try {
      await AuthService().requestRole(role);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud enviada. Un administrador la revisará.'),
        ),
      );
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar la solicitud: $e')),
      );
    }
  }

  Widget _panel({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = profile.role == AppRole.admin;
    final isCliente = profile.role == AppRole.cliente;
    final name = profile.fullName.isEmpty ? '' : ', ${profile.fullName}';

    final children = <Widget>[
      if (isAdmin) ...[
        _panel(
          context: context,
          title: 'Panel de cliente',
          icon: Icons.person_outline,
          children: [
            Text('Hola$name', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Rol: ${_roleLabel(profile.role)}'),
          ],
        ),
        const SizedBox(height: 12),
        _panel(
          context: context,
          title: 'Acceso administrativo',
          icon: Icons.admin_panel_settings,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Entrar al panel admin'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
          ],
        ),
      ] else ...[
        _panel(
          context: context,
          title: 'Panel de cliente',
          icon: Icons.person_outline,
          children: [
            Text('Hola$name', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Rol: ${_roleLabel(profile.role)}'),
            if (isCliente) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => _request(context, AppRole.transportista),
                child: const Text('Solicitar cuenta de transportista'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _request(context, AppRole.control),
                child: const Text('Solicitar acceso al panel de control'),
              ),
            ],
          ],
        ),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: children,
    );
  }
}

/// Pantalla completa del panel administrativo.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Panel administrativo')),
      body: const AdminView(),
    );
  }
}

class TransportistaView extends StatelessWidget {
  const TransportistaView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Panel del transportista'));
}

class ControlView extends StatelessWidget {
  const ControlView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Panel de control de líneas'));
}

/// Lista de solicitudes de rol que el administrador aprueba o rechaza.
class AdminView extends StatefulWidget {
  const AdminView({super.key});

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  final _auth = AuthService();
  late Future<List<Profile>> _pending = _auth.pendingRequests();

  Future<void> _decide(Profile p, {required bool approve}) async {
    try {
      await _auth.decideRequest(p.id, approve: approve);
      if (!mounted) return;
      setState(() => _pending = _auth.pendingRequests());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la solicitud: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Profile>>(
      future: _pending,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const Center(child: Text('No hay solicitudes pendientes'));
        }
        return ListView(
          children: [
            for (final p in list)
              ListTile(
                title: Text(p.fullName.isEmpty ? p.id : p.fullName),
                subtitle: Text('Solicita: ${_roleLabel(p.requestedRole!)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Rechazar',
                      icon: const Icon(Icons.close),
                      onPressed: () => _decide(p, approve: false),
                    ),
                    IconButton(
                      tooltip: 'Aprobar',
                      icon: const Icon(Icons.check),
                      onPressed: () => _decide(p, approve: true),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

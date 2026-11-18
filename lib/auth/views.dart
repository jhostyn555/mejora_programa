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
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel administrativo'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.approval), text: 'Solicitudes'),
              Tab(icon: Icon(Icons.manage_accounts), text: 'Roles'),
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Herramientas'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminView(),
            UserRolesView(),
            ToolsView(),
          ],
        ),
      ),
    );
  }
}

class TransportistaView extends StatelessWidget {
  const TransportistaView({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Panel del transportista (en construcción)'),
      );
}

/// El control gestiona las solicitudes de rol igual que el administrador.
class ControlView extends StatelessWidget {
  const ControlView({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Text(
              'Gestión de solicitudes de rol',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const Expanded(child: AdminView()),
        ],
      );
}

/// Lista de solicitudes de rol que admin o control aprueban o rechazan.
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

/// Asignacion de roles (cliente / transportista / control) a usuarios.
/// El rol 'admin' nunca aparece ni se puede asignar desde esta vista.
class UserRolesView extends StatefulWidget {
  const UserRolesView({super.key});

  @override
  State<UserRolesView> createState() => _UserRolesViewState();
}

class _UserRolesViewState extends State<UserRolesView> {
  final _auth = AuthService();
  final _search = TextEditingController();
  late Future<List<ManagedUser>> _users = _auth.listUsers();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _assign(ManagedUser user, AppRole role) async {
    if (role == user.role) return;
    final name = user.fullName.isEmpty ? user.email : user.fullName;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Asignar rol'),
        content: Text(
          'Asignar rol de ${_roleLabel(role)} a $name?\n'
          'Su vista cambiara al entrar de nuevo a Mi cuenta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _auth.adminSetRole(user.id, role);
      if (!mounted) return;
      setState(() => _users = _auth.listUsers());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rol de ${_roleLabel(role)} asignado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo asignar el rol: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Buscar usuario por nombre o correo',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ManagedUser>>(
            future: _users,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final query = _search.text.trim().toLowerCase();
              final list = (snap.data ?? []).where((c) {
                return c.fullName.toLowerCase().contains(query) ||
                    c.email.toLowerCase().contains(query);
              }).toList();
              if (list.isEmpty) {
                return const Center(
                  child: Text('No hay usuarios que coincidan'),
                );
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final user = list[index];
                  final options = <AppRole>[
                    AppRole.cliente,
                    AppRole.transportista,
                    AppRole.control,
                  ];
                  return ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      user.fullName.isEmpty ? user.email : user.fullName,
                    ),
                    subtitle: Text(
                      '${user.email}  •  Actual: ${_roleLabel(user.role)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButton<AppRole>(
                          value: options.contains(user.role)
                              ? user.role
                              : AppRole.cliente,
                          items: [
                            for (final role in options)
                              DropdownMenuItem<AppRole>(
                                value: role,
                                child: Text(_roleLabel(role)),
                              ),
                          ],
                          onChanged: (role) {
                            if (role != null) _assign(user, role);
                          },
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward, size: 16),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Opciones reservadas para el futuro dashboard. No hacen nada todavia.
class ToolsView extends StatelessWidget {
  const ToolsView({super.key});

  static const _options = [
    (icon: Icons.dashboard, title: 'Dashboard', subtitle: 'Metricas generales'),
    (icon: Icons.route, title: 'Lineas', subtitle: 'Administrar lineas de trufis'),
    (icon: Icons.alt_route, title: 'Rutas', subtitle: 'Rutas y recorridos'),
    (icon: Icons.people_alt, title: 'Transportistas', subtitle: 'Conductors y vehiculos'),
    (icon: Icons.bar_chart, title: 'Reportes', subtitle: 'Estadisticas y exportes'),
    (icon: Icons.notifications_none, title: 'Notificaciones', subtitle: 'Avisos a usuarios'),
    (icon: Icons.payments, title: 'Tarifas', subtitle: 'Precios y descuentos'),
    (icon: Icons.settings_outlined, title: 'Configuracion', subtitle: 'Ajustes del sistema'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _options.length,
      itemBuilder: (context, index) {
        final option = _options[index];
        return Card(
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ComingSoonScreen(title: option.title),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(option.icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(
                    option.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ComingSoonScreen extends StatelessWidget {
  final String title;

  const ComingSoonScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 64),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('En construcción'),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import 'admin_service.dart';

/// Panel administrativo unificado, alineado al esquema real de Supabase.
///
/// Pestañas:
///  * **Usuarios** — buscador por nombre/correo/rol y cambio de rol.
///  * **Solicitudes** — aprobación / rechazo de solicitudes de rol.
///  * **Líneas** — CRUD sobre `public.linea` (id_linea, nombre_linea, ...).
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _service = AdminService();
  final _search = TextEditingController();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _lineas = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadUsers(),
        _loadPending(),
        _loadLineas(),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadUsers() async {
    final q = _search.text.trim().isEmpty ? null : _search.text.trim();
    final list = await _service.searchUsers(query: q);
    if (mounted) setState(() => _users = list);
  }

  Future<void> _loadPending() async {
    final list = await _service.pendingRequests();
    if (mounted) setState(() => _pending = list);
  }

  Future<void> _loadLineas() async {
    final list = await _service.getLineas();
    if (mounted) setState(() => _lineas = list);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static const _roleOptions = [
    AppRole.cliente,
    AppRole.chofer,
    AppRole.control,
    AppRole.admin,
  ];

  String _roleLabel(AppRole r) => switch (r) {
        AppRole.cliente => 'Cliente',
        AppRole.chofer => 'Chofer',
        AppRole.control => 'Control',
        AppRole.admin => 'Administrador',
      };

  Future<void> _cambiarRol(Map<String, dynamic> u) async {
    final currentRole = AppRole.values.firstWhere(
      (r) => r.name == u['role'],
      orElse: () => AppRole.cliente,
    );

    final newRole = await showDialog<AppRole>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar rol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usuario: ${u['full_name'] ?? u['email']}'),
            const SizedBox(height: 8),
            Text('Rol actual: ${_roleLabel(currentRole)}'),
            const SizedBox(height: 16),
            const Text('Nuevo rol:'),
            DropdownButton<AppRole>(
              value: currentRole,
              items: _roleOptions
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(_roleLabel(r)),
                      ))
                  .toList(),
              onChanged: (r) => Navigator.pop(ctx, r),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (newRole == null || newRole == currentRole || !mounted) return;

    try {
      await _service.setUserRole(u['id'], newRole);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rol cambiado a ${_roleLabel(newRole)}')),
      );
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar el rol: $e')),
      );
    }
  }

  Future<void> _aprobarRechazar(Map<String, dynamic> u, bool approve) async {
    try {
      await _service.decideRequest(u['id'], approve);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Solicitud aprobada: ${u['full_name']}'
                : 'Solicitud rechazada: ${u['full_name']}',
          ),
        ),
      );
      _loadPending();
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la solicitud: $e')),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Pestaña Usuarios
  // -------------------------------------------------------------------------

  Widget _usuariosTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _loadUsers(),
            decoration: const InputDecoration(
              labelText: 'Buscar por nombre, correo o rol',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _users.isEmpty
                  ? const Center(child: Text('No se encontraron usuarios'))
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, i) {
                        final u = _users[i];
                        final role = AppRole.values.firstWhere(
                          (r) => r.name == u['role'],
                          orElse: () => AppRole.cliente,
                        );
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(
                            (u['full_name'] as String).isNotEmpty
                                ? u['full_name'] as String
                                : u['email'] as String,
                          ),
                          subtitle: Text(
                            '${u['email']}  •  ${_roleLabel(role)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Cambiar rol',
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _cambiarRol(u),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Pestaña Solicitudes
  // -------------------------------------------------------------------------

  Widget _solicitudesTab() {
    return _pending.isEmpty
        ? const Center(child: Text('No hay solicitudes de rol pendientes'))
        : ListView.builder(
            itemCount: _pending.length,
            itemBuilder: (context, i) {
              final u = _pending[i];
              final solicitado = AppRole.values.firstWhere(
                (r) => r.name == u['requested_role'],
                orElse: () => AppRole.cliente,
              );
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_add)),
                title: Text(
                  (u['full_name'] as String).isNotEmpty
                      ? u['full_name'] as String
                      : u['id'].toString(),
                ),
                subtitle: Text('Solicita ser ${_roleLabel(solicitado)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Rechazar',
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => _aprobarRechazar(u, false),
                    ),
                    IconButton(
                      tooltip: 'Aprobar',
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () => _aprobarRechazar(u, true),
                    ),
                  ],
                ),
              );
            },
          );
  }

  // -------------------------------------------------------------------------
  // Pestaña Líneas (public.linea)
  // -------------------------------------------------------------------------

  Widget _lineasTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la línea',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (val) async {
                    if (val.trim().isNotEmpty) {
                      await _service.createLinea(nombre: val.trim());
                      _loadLineas();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Crear'),
                onPressed: () async {
                  final controller = TextEditingController();
                  final nombre = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Nueva línea'),
                      content: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la línea',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.pop(ctx, controller.text),
                          child: const Text('Crear'),
                        ),
                      ],
                    ),
                  );
                  if (nombre != null && nombre.trim().isNotEmpty) {
                    await _service.createLinea(nombre: nombre.trim());
                    _loadLineas();
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _lineas.isEmpty
              ? const Center(child: Text('No hay líneas registradas'))
              : ListView.builder(
                  itemCount: _lineas.length,
                  itemBuilder: (context, i) {
                    final l = _lineas[i];
                    final id = l['id_linea'] as int;
                    final nombre = l['nombre_linea'] as String? ?? '';
                    final descripcion = l['descripcion'] as String? ?? '';
                    final activo = l['activo'] == true;
                    return Dismissible(
                      key: ValueKey(id),
                      onDismissed: (_) async {
                        await _service.deleteLinea(id);
                        _loadLineas();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Línea eliminada')),
                          );
                        }
                      },
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            nombre.isNotEmpty
                                ? nombre[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(nombre),
                        subtitle: Text(
                          descripcion.isNotEmpty
                              ? descripcion
                              : 'Sin descripción',
                        ),
                        trailing: Switch(
                          value: activo,
                          onChanged: (val) async {
                            await _service.updateLinea(id, activo: val);
                            _loadLineas();
                          },
                        ),
                        onTap: () async {
                          final nombreCtrl =
                              TextEditingController(text: nombre);
                          final descCtrl =
                              TextEditingController(text: descripcion);
                          await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Editar línea'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: nombreCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: descCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Descripción',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () async {
                                    await _service.updateLinea(
                                      id,
                                      nombre: nombreCtrl.text,
                                      descripcion: descCtrl.text,
                                    );
                                    _loadLineas();
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                  child: const Text('Guardar'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel administrativo'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.manage_accounts), text: 'Usuarios'),
              Tab(icon: Icon(Icons.app_registration), text: 'Solicitudes'),
              Tab(icon: Icon(Icons.route), text: 'Líneas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _usuariosTab(),
            _solicitudesTab(),
            _lineasTab(),
          ],
        ),
      ),
    );
  }
}

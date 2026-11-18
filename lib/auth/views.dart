import 'package:flutter/material.dart';

import '../services/transit_service.dart';
import 'auth_service.dart';

String _roleLabel(AppRole role) => switch (role) {
      AppRole.cliente => 'Cliente',
      AppRole.chofer => 'Chofer',
      AppRole.control => 'Control de líneas',
      AppRole.admin => 'Administrador',
    };

/// ---------------------------------------------------------------------------
/// CLIENTE
///   Vista principal = la app de Trufi (mapa + planificador) que ya es la
///   home de runTrufiApp. Aquí sólo va la cuenta del cliente: perfil y
///   avisos. NO se muestran botones de panel ni de admin, como pediste.
/// ---------------------------------------------------------------------------
class ClienteView extends StatefulWidget {
  final Profile profile;
  final VoidCallback onChanged;

  const ClienteView({super.key, required this.profile, required this.onChanged});

  @override
  State<ClienteView> createState() => _ClienteViewState();
}

class _ClienteViewState extends State<ClienteView> {
  final _transit = TransitService();
  late Future<List<Map<String, dynamic>>> _avisos =
      _transit.myAvisosAsCliente();

  void _reload() => setState(() {
        _avisos = _transit.myAvisosAsCliente();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.profile.fullName.isEmpty
        ? ''
        : ', ${widget.profile.fullName}';
    final isAdmin = widget.profile.role == AppRole.admin;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Mi cuenta',
                        style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Hola$name',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Rol: ${_roleLabel(widget.profile.role)}'),
                const SizedBox(height: 4),
                Text(
                  isAdmin
                      ? 'Tienes acceso al panel administrativo.'
                      : 'Esta es tu vista de cliente. Usa el mapa y el '
                          'planificador de rutas desde la pantalla principal.',
                  style: theme.textTheme.bodySmall,
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.admin_panel_settings),
                    label: const Text('Entrar al panel admin'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdminScreen()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Avisos para ti', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _avisos,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                heightFactor: 4,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (snap.hasError) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('No se pudieron cargar avisos'),
                  subtitle: Text('${snap.error}'),
                ),
              );
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No tienes avisos.',
                      style: TextStyle(color: Colors.grey)),
                ),
              );
            }
            return Column(
              children: [
                for (final a in list)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: Text((a['mensaje'] ?? '') as String),
                      subtitle: Text(_fmtDate(a['fecha_hora'])),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (widget.profile.role == AppRole.cliente)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('¿Eres chofer o control?',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.directions_bus),
                    label: const Text('Solicitar cuenta de chofer'),
                    onPressed: () => _requestRole(AppRole.chofer),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Solicitar acceso de control'),
                    onPressed: () => _requestRole(AppRole.control),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _requestRole(AppRole role) async {
    try {
      await AuthService().requestRole(role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud enviada. Un administrador la revisará.'),
        ),
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar la solicitud: $e')),
      );
    }
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.length >= 16) return s.substring(0, 16).replaceAll('T', ' ');
    return s;
  }
}

/// ---------------------------------------------------------------------------
/// CHOFER
///   Panel funcional: vehículo asignado, viaje activo, historial, multas,
///   actualización de ubicación.
/// ---------------------------------------------------------------------------
class ChoferView extends StatefulWidget {
  const ChoferView({super.key});

  @override
  State<ChoferView> createState() => _ChoferViewState();
}

class _ChoferViewState extends State<ChoferView> {
  final _transit = TransitService();
  late Future<Map<String, dynamic>?> _vehicle = _transit.myVehicle();
  late Future<List<Map<String, dynamic>>> _history = _transit.myTripHistory();
  late Future<List<Map<String, dynamic>>> _fines = _transit.myFines();
  bool _locating = false;
  bool _tripBusy = false;

  void _reloadAll() => setState(() {
        _vehicle = _transit.myVehicle();
        _history = _transit.myTripHistory();
        _fines = _transit.myFines();
      });

  Future<void> _updateLocation() async {
    setState(() => _locating = true);
    try {
      // Sin plugin de geolocalización en este PR: pedimos lat/lng por
      // defecto al centro de Cochabamba. Cuando se añada geolocator,
      // reemplazar por Position actual.
      const lat = -17.3988354;
      const lng = -66.1626903;
      await _transit.updateMyLocation(lat, lng);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación actualizada')),
      );
      _reloadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $e')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _toggleTrip(Map<String, dynamic>? vehicle) async {
    if (vehicle == null) return;
    setState(() => _tripBusy = true);
    try {
      final vehId = vehicle['id_vehiculo'] as int;
      final lineaId = vehicle['id_linea'] as int?;
      if (lineaId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tu vehículo no tiene línea asignada')),
        );
        return;
      }
      // Buscar la primera ruta de la línea.
      final rutas = await _transit.listRoutes(idLinea: lineaId);
      if (rutas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La línea no tiene rutas')),
        );
        return;
      }
      final rutaId = rutas.first['id_ruta'] as int;
      final history = await _history;
      final activeTrip = history
          .where((t) => t['fecha_fin'] == null)
          .toList();
      if (activeTrip.isEmpty) {
        await _transit.startTrip(vehiculoId: vehId, rutaId: rutaId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Viaje iniciado')),
        );
      } else {
        await _transit.endActiveTrip();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Viaje finalizado')),
        );
      }
      _reloadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _tripBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // --- Vehículo asignado ---
        FutureBuilder<Map<String, dynamic>?>(
          future: _vehicle,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                heightFactor: 4,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (snap.hasError) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('No se pudo cargar el vehículo'),
                  subtitle: Text('${snap.error}'),
                ),
              );
            }
            final v = snap.data;
            if (v == null) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.directions_bus,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Sin vehículo asignado',
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Cuando un administrador te asigne un vehículo, '
                        'lo verás aquí.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }
            final placa = v['placa'] as String? ?? '—';
            final linea = v['id_linea'] as int?;
            final lat = v['latitud'] as double?;
            final lng = v['longitud'] as double?;
            final active = v['activo'] as bool? ?? false;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.directions_bus,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Vehículo asignado',
                            style: theme.textTheme.titleMedium),
                        const Spacer(),
                        Chip(
                          label: Text(active ? 'Activo' : 'Inactivo'),
                          backgroundColor: active
                              ? Colors.green.shade100
                              : Colors.grey.shade200,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _kv('Placa', placa),
                    if (linea != null) _kv('Línea', '#$linea'),
                    if (lat != null && lng != null)
                      _kv('Ubicación', '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: _locating
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.my_location),
                            label: const Text('Actualizar ubicación'),
                            onPressed: _locating ? null : _updateLocation,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _history,
                      builder: (context, h) {
                        if (h.connectionState != ConnectionState.done) {
                          return const SizedBox.shrink();
                        }
                        final activeTrip = (h.data ?? [])
                            .where((t) => t['fecha_fin'] == null)
                            .toList();
                        final hasActive = activeTrip.isNotEmpty;
                        return FilledButton.tonalIcon(
                          icon: hasActive
                              ? const Icon(Icons.stop_circle_outlined)
                              : const Icon(Icons.play_arrow),
                          label: Text(hasActive ? 'Finalizar viaje' : 'Iniciar viaje'),
                          onPressed: _tripBusy ? null : () => _toggleTrip(v),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // --- Historial de viajes ---
        Text('Historial de viajes', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _history,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                heightFactor: 3,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (snap.hasError) {
              return Text('Error: ${snap.error}');
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Sin viajes registrados.',
                      style: TextStyle(color: Colors.grey)),
                ),
              );
            }
            return Column(
              children: [
                for (final t in list.take(10))
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(
                        'Viaje #${t['id_historial_viaje']} • '
                        'Ruta ${t['id_ruta']}',
                      ),
                      subtitle: Text(
                        'Inicio: ${_fmtDate(t['fecha_inicio'])}\n'
                        'Fin: ${t['fecha_fin'] == null ? 'En curso' : _fmtDate(t['fecha_fin'])}',
                      ),
                      isThreeLine: true,
                      trailing: t['cantidad_pasajeros'] != null
                          ? Chip(
                              label: Text('${t['cantidad_pasajeros']} pax'),
                            )
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // --- Multas ---
        Text('Multas', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _fines,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                heightFactor: 3,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (snap.hasError) {
              return Text('Error: ${snap.error}');
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Sin multas. ¡Bien hecho!',
                      style: TextStyle(color: Colors.grey)),
                ),
              );
            }
            return Column(
              children: [
                for (final m in list)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.gavel),
                      title: Text(m['motivo'] as String? ?? 'Multa'),
                      subtitle: Text(
                        'Monto: ${m['monto']} • ${m['estado']} • '
                        '${_fmtDate(m['fecha_hora'])}',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$k:  ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.length >= 16) return s.substring(0, 16).replaceAll('T', ' ');
    return s;
  }
}

/// ---------------------------------------------------------------------------
/// CONTROL
///   Pestañas: Solicitudes de rol, Líneas, Vehículos en vivo, Choferes,
///   Multas, Avisos.
/// ---------------------------------------------------------------------------
class ControlView extends StatelessWidget {
  const ControlView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Panel de control de líneas',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.approval), text: 'Solicitudes'),
              Tab(icon: Icon(Icons.alt_route), text: 'Líneas'),
              Tab(icon: Icon(Icons.directions_bus), text: 'Vehículos'),
              Tab(icon: Icon(Icons.people_alt), text: 'Choferes'),
              Tab(icon: Icon(Icons.gavel), text: 'Multas'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                AdminView(),
                _ControlLinesTab(),
                _ControlVehiclesTab(),
                _ControlChoferesTab(),
                _ControlFinesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlLinesTab extends StatefulWidget {
  const _ControlLinesTab();

  @override
  State<_ControlLinesTab> createState() => _ControlLinesTabState();
}

class _ControlLinesTabState extends State<_ControlLinesTab> {
  final _transit = TransitService();
  late Future<List<Map<String, dynamic>>> _lines = _transit.myManagedLines();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _lines,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const Center(child: Text('No gestionas ninguna línea'));
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final l = list[i];
            return ListTile(
              leading: const Icon(Icons.alt_route),
              title: Text(l['nombre_linea'] as String? ?? 'Línea ${l['id_linea']}'),
              subtitle: Text(l['descripcion'] as String? ?? ''),
              trailing: Chip(label: Text(l['activo'] == true ? 'Activa' : 'Inactiva')),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _LineDetailScreen(lineId: l['id_linea'] as int),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LineDetailScreen extends StatelessWidget {
  final int lineId;
  const _LineDetailScreen({required this.lineId});

  @override
  Widget build(BuildContext context) {
    final transit = TransitService();
    return Scaffold(
      appBar: AppBar(title: Text('Línea #$lineId')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: transit.listRoutes(idLinea: lineId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text('Sin rutas'));
          }
          return ListView(
            children: [
              for (final r in list)
                ListTile(
                  leading: const Icon(Icons.route),
                  title: Text(r['nombre_ruta'] as String? ?? 'Ruta ${r['id_ruta']}'),
                  subtitle: Text(r['descripcion_trazado'] as String? ?? ''),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ControlVehiclesTab extends StatefulWidget {
  const _ControlVehiclesTab();

  @override
  State<_ControlVehiclesTab> createState() => _ControlVehiclesTabState();
}

class _ControlVehiclesTabState extends State<_ControlVehiclesTab> {
  final _transit = TransitService();
  late Future<List<Map<String, dynamic>>> _vehicles =
      _transit.activeVehicles();

  void _reload() => setState(() {
        _vehicles = _transit.activeVehicles();
      });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(
                child: Text('Vehículos activos en tiempo real'),
              ),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: _reload,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _vehicles,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return const Center(child: Text('No hay vehículos activos'));
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final v = list[i];
                  final lat = v['latitud'] as double?;
                  final lng = v['longitud'] as double?;
                  return ListTile(
                    leading: const Icon(Icons.directions_bus),
                    title: Text('Placa: ${v['placa'] ?? '—'}'),
                    subtitle: Text(
                      'Chofer: ${v['nombre_chofer'] ?? '—'} • '
                      'Línea: ${v['nombre_linea'] ?? '—'}',
                    ),
                    trailing: lat != null && lng != null
                        ? Chip(label: Text('${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}'))
                        : null,
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

class _ControlChoferesTab extends StatefulWidget {
  const _ControlChoferesTab();

  @override
  State<_ControlChoferesTab> createState() => _ControlChoferesTabState();
}

class _ControlChoferesTabState extends State<_ControlChoferesTab> {
  final _transit = TransitService();
  late Future<List<Map<String, dynamic>>> _choferes = _transit.allChoferes();

  void _reload() => setState(() {
        _choferes = _transit.allChoferes();
      });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(child: Text('Choferes registrados')),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: _reload,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _choferes,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return const Center(child: Text('No hay choferes'));
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  final persona = c['persona'];
                  String nombre = '';
                  String ci = '';
                  String telefono = '';
                  if (persona is Map) {
                    nombre = persona['nombre'] as String? ?? '';
                    ci = persona['ci'] as String? ?? '';
                    telefono = persona['telefono'] as String? ?? '';
                  }
                  return ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(nombre.isEmpty ? 'Chofer #${c['id_chofer']}' : nombre),
                    subtitle: Text(
                      'CI: $ci • Lic: ${c['licencia'] ?? '—'} • '
                      'Tel: $telefono',
                    ),
                    trailing: Chip(
                      label: Text(c['activo'] == true ? 'Activo' : 'Inactivo'),
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

class _ControlFinesTab extends StatefulWidget {
  const _ControlFinesTab();

  @override
  State<_ControlFinesTab> createState() => _ControlFinesTabState();
}

class _ControlFinesTabState extends State<_ControlFinesTab> {
  final _transit = TransitService();
  late Future<List<Map<String, dynamic>>> _fines = _transit.finesIssuedByMe();

  void _reload() => setState(() {
        _fines = _transit.finesIssuedByMe();
      });

  Future<void> _createFine() async {
    final choferIdCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();
    final montoCtrl = TextEditingController(text: '0');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva multa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: choferIdCtrl,
              decoration: const InputDecoration(
                labelText: 'ID del chofer',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montoCtrl,
              decoration: const InputDecoration(
                labelText: 'Monto (Bs.)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final choferId = int.tryParse(choferIdCtrl.text);
    final monto = double.tryParse(montoCtrl.text);
    if (choferId == null || monto == null || motivoCtrl.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos inválidos')),
      );
      return;
    }
    try {
      await _transit.createFine(
        choferId: choferId,
        motivo: motivoCtrl.text,
        monto: monto,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Multa registrada')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(child: Text('Multas que has emitido')),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nueva'),
                onPressed: _createFine,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _fines,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return const Center(child: Text('No has emitido multas'));
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final m = list[i];
                  return ListTile(
                    leading: const Icon(Icons.gavel),
                    title: Text(m['motivo'] as String? ?? 'Multa'),
                    subtitle: Text(
                      'Chofer: ${m['id_chofer']} • '
                      'Monto: ${m['monto']} • '
                      '${m['estado']} • '
                      '${m['fecha_hora']?.toString().substring(0, 16)}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        await _transit.setFineStatus(
                            m['id_multa'] as int, v);
                        _reload();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'pendiente', child: Text('Pendiente')),
                        PopupMenuItem(value: 'pagada', child: Text('Pagada')),
                        PopupMenuItem(value: 'anulada', child: Text('Anulada')),
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

/// ---------------------------------------------------------------------------
/// ADMIN
///   Pantalla completa del panel administrativo. Mantiene las 3 pestañas
///   originales (Solicitudes, Roles, Herramientas).
/// ---------------------------------------------------------------------------
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

/// Asignacion de roles (cliente / chofer / control) a usuarios.
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
                    AppRole.chofer,
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
    (icon: Icons.people_alt, title: 'Choferes', subtitle: 'Conductores y vehiculos'),
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

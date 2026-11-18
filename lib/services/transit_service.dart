import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../auth/supabase_config.dart';

/// Capa de datos para las 14 tablas de transporte (linea, ruta, vehiculo,
/// chofer, control, cliente, persona, aviso, multa, pago, historial_*).
///
/// Usa el mismo `Supabase.instance.client` que AuthService. Si Supabase no
/// está configurado, todos los métodos lanzan [StateError] con el mensaje
/// habitual; las vistas deben comprobar `isSupabaseConfigured` antes.
class TransitService {
  SupabaseClient get _client => Supabase.instance.client;

  void _requireConfig() {
    if (!isSupabaseInitialized) {
      if (supabaseInitWarning != null) throw StateError(supabaseInitWarning!);
      if (!isSupabaseConfigured) throw StateError(supabaseMissingConfigMessage);
      throw StateError('Supabase no fue inicializado.');
    }
  }

  // ===================== MODELOS DE DATOS =====================

  /// Vehículo con su línea y nombre del chofer (para la vista de control).
  static const String activeVehicleFields =
      'id_vehiculo, placa, latitud, longitud, id_chofer, id_linea, nombre_linea, nombre_chofer';

  Map<String, dynamic> _clean(Map<String, dynamic> row) {
    return Map<String, dynamic>.from(row);
  }

  // ===================== LÍNEAS Y RUTAS (lectura pública) =====================

  /// Lista de líneas activas. Visible para cualquier usuario autenticado.
  Future<List<Map<String, dynamic>>> listLines({bool activeOnly = true}) async {
    _requireConfig();
    var q = _client.from('linea').select().order('nombre_linea');
    if (activeOnly) q = q.eq('activo', true);
    final rows = await q;
    return rows.map(_clean).toList();
  }

  /// Rutas de una línea (o todas si idLinea es null).
  Future<List<Map<String, dynamic>>> listRoutes({int? idLinea}) async {
    _requireConfig();
    var q = _client.from('ruta').select().order('nombre_ruta');
    if (idLinea != null) q = q.eq('id_linea', idLinea);
    final rows = await q;
    return rows.map(_clean).toList();
  }

  // ===================== CHOFER =====================

  /// Vehículo asignado al chofer autenticado.
  /// Usa el RPC `my_assigned_vehicle` para respetar la RLS.
  Future<Map<String, dynamic>?> myVehicle() async {
    _requireConfig();
    final rows = await _client.rpc('my_assigned_vehicle');
    if (rows is! List || rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  /// Historial de viajes del chofer autenticado.
  Future<List<Map<String, dynamic>>> myTripHistory({int limit = 50}) async {
    _requireConfig();
    final rows = await _client
        .from('historial_vehiculo_viaje')
        .select()
        .eq('id_chofer', await _myChoferId())
        .order('fecha_inicio', ascending: false)
        .limit(limit);
    return rows.map(_clean).toList();
  }

  /// Multas del chofer autenticado.
  Future<List<Map<String, dynamic>>> myFines() async {
    _requireConfig();
    final rows = await _client
        .from('multa')
        .select()
        .eq('id_chofer', await _myChoferId())
        .order('fecha_hora', ascending: false);
    return rows.map(_clean).toList();
  }

  /// Actualiza la ubicación del vehículo del chofer.
  Future<void> updateMyLocation(double lat, double lng) async {
    _requireConfig();
    await _client.rpc(
      'upsert_vehicle_location',
      params: {'new_lat': lat, 'new_lng': lng},
    );
  }

  /// Registra un reporte (incidente, retraso, etc.) del chofer.
  Future<void> reportIncident({
    required int choferId,
    required String estado,
    required String observacion,
  }) async {
    _requireConfig();
    await _client.rpc(
      'report_incident',
      params: {
        'p_id_chofer': choferId,
        'p_estado': estado,
        'p_observacion': observacion,
      },
    );
  }

  /// Inicia un viaje: inserta en historial_vehiculo_viaje.
  Future<void> startTrip({
    required int vehiculoId,
    required int rutaId,
    int? pasajeros,
  }) async {
    _requireConfig();
    final choferId = await _myChoferId();
    await _client.from('historial_vehiculo_viaje').insert({
      'id_vehiculo': vehiculoId,
      'id_ruta': rutaId,
      'id_chofer': choferId,
      'fecha_inicio': DateTime.now().toUtc().toIso8601String(),
      'cantidad_pasajeros': pasajeros ?? 0,
    });
  }

  /// Cierra el viaje activo del chofer (sin fecha_fin).
  Future<void> endActiveTrip({String? observacionTiempo}) async {
    _requireConfig();
    final choferId = await _myChoferId();
    await _client
        .from('historial_vehiculo_viaje')
        .update({
          'fecha_fin': DateTime.now().toUtc().toIso8601String(),
          'observacion_tiempo': observacionTiempo,
        })
        .eq('id_chofer', choferId)
        .is('fecha_fin', null);
  }

  // ===================== CONTROL =====================

  /// Líneas que gestiona el control autenticado (o todas si es admin).
  Future<List<Map<String, dynamic>>> myManagedLines() async {
    _requireConfig();
    final rows = await _client.rpc('my_lines');
    if (rows is! List) return [];
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// Vehículos activos con chofer y línea, para el mapa de control.
  Future<List<Map<String, dynamic>>> activeVehicles() async {
    _requireConfig();
    final rows = await _client.rpc('active_vehicles');
    if (rows is! List) return [];
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// Choferes de una línea (para el panel de control).
  /// Hace tres consultas y los une en Dart para no depender de FK.
  Future<List<Map<String, dynamic>>> choferesOfLine(int idLinea) async {
    _requireConfig();
    // 1) Vehículos activos de la línea -> sus choferes.
    final vehiculos = await _client
        .from('vehiculo')
        .select('id_chofer')
        .eq('id_linea', idLinea)
        .eq('activo', true);
    if (vehiculos.isEmpty) return [];
    final choferIds = vehiculos
        .map((v) => v['id_chofer'])
        .whereType<int>()
        .toSet();
    if (choferIds.isEmpty) return [];
    // 2) Choferes con esos ids.
    final choferesRows = await _client
        .from('chofer')
        .select('id_chofer, id_persona, licencia, foto_url, activo')
        .inFilter('id_chofer', choferIds.toList());
    // 3) Personas correspondientes.
    final personaIds = choferesRows
        .map((c) => c['id_persona'])
        .whereType<int>()
        .toSet();
    final personasRows = personaIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
            .from('persona')
            .select('id_persona, nombre, ci, telefono')
            .inFilter('id_persona', personaIds.toList());
    final personaById = <int, Map<String, dynamic>>{
      for (final p in personasRows)
        if (p['id_persona'] is int) p['id_persona'] as int: Map<String, dynamic>.from(p),
    };
    return choferesRows.map((c) {
      final m = Map<String, dynamic>.from(c);
      final pid = c['id_persona'];
      m['persona'] = (pid is int && personaById.containsKey(pid))
          ? personaById[pid]
          : <String, dynamic>{};
      return m;
    }).toList();
  }

  /// Lista todos los choferes (solo control/admin).
  /// Hace dos consultas y los une en Dart para no depender de FK.
  Future<List<Map<String, dynamic>>> allChoferes() async {
    _requireConfig();
    final choferesRows = await _client
        .from('chofer')
        .select('id_chofer, id_persona, licencia, foto_url, activo')
        .order('activo', ascending: false);
    final personasRows = await _client
        .from('persona')
        .select('id_persona, nombre, ci, telefono');
    final personaById = <int, Map<String, dynamic>>{
      for (final p in personasRows)
        if (p['id_persona'] is int) p['id_persona'] as int: Map<String, dynamic>.from(p),
    };
    return choferesRows.map((c) {
      final m = Map<String, dynamic>.from(c);
      final pid = c['id_persona'];
      if (pid is int && personaById.containsKey(pid)) {
        m['persona'] = personaById[pid];
      } else {
        m['persona'] = {};
      }
      return m;
    }).toList();
  }

  /// Multas que el control ha emitido.
  Future<List<Map<String, dynamic>>> finesIssuedByMe() async {
    _requireConfig();
    final controlId = await _myControlId();
    if (controlId == null) return [];
    final rows = await _client
        .from('multa')
        .select()
        .eq('id_control', controlId)
        .order('fecha_hora', ascending: false);
    return rows.map(_clean).toList();
  }

  /// Crea una multa (solo control/admin).
  Future<void> createFine({
    required int choferId,
    required String motivo,
    required double monto,
  }) async {
    _requireConfig();
    final controlId = await _myControlId();
    await _client.from('multa').insert({
      'id_chofer': choferId,
      'id_control': controlId,
      'motivo': motivo,
      'monto': monto,
      'fecha_hora': DateTime.now().toUtc().toIso8601String(),
      'estado': 'pendiente',
    });
  }

  /// Cambia el estado de una multa (pagada, anulada, etc.).
  Future<void> setFineStatus(int fineId, String estado) async {
    _requireConfig();
    await _client
        .from('multa')
        .update({'estado': estado, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id_multa', fineId);
  }

  /// Avisos creados por el control autenticado.
  Future<List<Map<String, dynamic>>> myAvisos() async {
    _requireConfig();
    final controlId = await _myControlId();
    if (controlId == null) return [];
    final rows = await _client
        .from('aviso')
        .select()
        .eq('id_control', controlId)
        .order('fecha_hora', ascending: false);
    return rows.map(_clean).toList();
  }

  /// Crea un aviso (a un cliente específico o a una ruta entera).
  Future<int> createAviso({
    String? mensaje,
    int? rutaId,
    int? clienteId,
  }) async {
    _requireConfig();
    final id = await _client.rpc(
      'create_aviso',
      params: {
        'p_mensaje': mensaje,
        'p_id_ruta': rutaId,
        'p_id_cliente': clienteId,
      },
    );
    return (id is int) ? id : int.tryParse('$id') ?? 0;
  }

  // ===================== CLIENTE =====================

  /// Avisos dirigidos al cliente autenticado.
  Future<List<Map<String, dynamic>>> myAvisosAsCliente() async {
    _requireConfig();
    final clienteId = await _myClienteId();
    if (clienteId == null) return [];
    final rows = await _client
        .from('aviso')
        .select()
        .eq('id_cliente', clienteId)
        .order('fecha_hora', ascending: false);
    return rows.map(_clean).toList();
  }

  /// Pagos del cliente autenticado.
  Future<List<Map<String, dynamic>>> myPayments() async {
    _requireConfig();
    final clienteId = await _myClienteId();
    if (clienteId == null) return [];
    final rows = await _client
        .from('pago')
        .select()
        .eq('id_cliente', clienteId)
        .order('fecha_hora', ascending: false);
    return rows.map(_clean).toList();
  }

  // ===================== REALTIME =====================

  /// Suscripción a cambios en `vehiculo` (ubicación de choferes en vivo).
  /// Solo有意义 para la vista de control / cliente-map.
  Stream<List<Map<String, dynamic>>> watchActiveVehicles() {
    _requireConfig();
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    Future<void> refresh() async {
      try {
        final rows = await _client
            .from('vehiculo')
            .select('id_vehiculo, placa, latitud, longitud, id_chofer, id_linea, activo')
            .eq('activo', true);
        controller.add(rows.map(_clean).toList());
      } catch (e) {
        controller.addError(e);
      }
    }

    refresh();
    final channel = _client
        .channel('vehiculos_active')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehiculo',
          callback: (_) => refresh(),
        )
        .subscribe();

    controller.onCancel = () {
      _client.removeChannel(channel);
    };

    return controller.stream;
  }

  // ===================== HELPERS INTERNOS =====================

  Future<int?> _myChoferId() async {
    final v = await _client.rpc('my_chofer_id');
    return v is int ? v : int.tryParse('$v');
  }

  Future<int?> _myControlId() async {
    final v = await _client.rpc('my_control_id');
    return v is int ? v : int.tryParse('$v');
  }

  Future<int?> _myClienteId() async {
    final v = await _client.rpc('my_cliente_id');
    return v is int ? v : int.tryParse('$v');
  }

  /// Role actual leído desde el backend (más confiable que cachearlo).
  Future<AppRole> currentRole() async {
    _requireConfig();
    final v = await _client.rpc('my_role');
    final s = v is String ? v : v.toString();
    return roleFromString(s);
  }
}

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../auth/supabase_config.dart';

class TransitService {
  SupabaseClient get _client => Supabase.instance.client;

  void _requireConfig() {
    if (!isSupabaseInitialized) {
      if (supabaseInitWarning != null) throw StateError(supabaseInitWarning!);
      if (!isSupabaseConfigured) throw StateError(supabaseMissingConfigMessage);
      throw StateError('Supabase no fue inicializado.');
    }
  }

  static const String activeVehicleFields =
      'id_vehiculo, placa, latitud, longitud, id_chofer, id_linea, nombre_linea, nombre_chofer';

  Map<String, dynamic> _clean(Map<String, dynamic> row) {
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> listLines({bool activeOnly = true}) async {
    _requireConfig();
    var query = _client.from('linea').select();
    if (activeOnly) {
      query = query.eq('activo', true);
    }
    final rows = await query.order('nombre_linea');
    return rows.map(_clean).toList();
  }

  Future<List<Map<String, dynamic>>> listRoutes({int? idLinea}) async {
    _requireConfig();
    var query = _client.from('ruta').select();
    if (idLinea != null) {
      query = query.eq('id_linea', idLinea);
    }
    final rows = await query.order('nombre_ruta');
    return rows.map(_clean).toList();
  }

  Future<Map<String, dynamic>?> myVehicle() async {
    _requireConfig();
    final rows = await _client.rpc('my_assigned_vehicle');
    if (rows is! List || rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<List<Map<String, dynamic>>> myTripHistory({int limit = 50}) async {
    _requireConfig();
    final choferId = await _myChoferId();
    if (choferId == null) return [];
    final rows = await _client
        .from('historial_vehiculo_viaje')
        .select()
        .eq('id_chofer', choferId)
        .order('fecha_inicio', ascending: false)
        .limit(limit);
    return rows.map(_clean).toList();
  }

  Future<List<Map<String, dynamic>>> myFines() async {
    _requireConfig();
    final choferId = await _myChoferId();
    if (choferId == null) return [];
    final rows = await _client
        .from('multa')
        .select()
        .eq('id_chofer', choferId)
        .order('fecha_hora', ascending: false);
    return rows.map(_clean).toList();
  }

  Future<void> updateMyLocation(double lat, double lng) async {
    _requireConfig();
    await _client.rpc(
      'upsert_vehicle_location',
      params: {'new_lat': lat, 'new_lng': lng},
    );
  }

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

  Future<void> startTrip({
    required int vehiculoId,
    required int rutaId,
    int? pasajeros,
  }) async {
    _requireConfig();
    final choferId = await _myChoferId();
    if (choferId == null) return;
    await _client.from('historial_vehiculo_viaje').insert({
      'id_vehiculo': vehiculoId,
      'id_ruta': rutaId,
      'id_chofer': choferId,
      'fecha_inicio': DateTime.now().toUtc().toIso8601String(),
      'cantidad_pasajeros': pasajeros ?? 0,
    });
  }

  Future<void> endActiveTrip({String? observacionTiempo}) async {
    _requireConfig();
    final choferId = await _myChoferId();
    if (choferId == null) return;
    await _client
        .from('historial_vehiculo_viaje')
        .update({
          'fecha_fin': DateTime.now().toUtc().toIso8601String(),
          'observacion_tiempo': observacionTiempo,
        })
        .eq('id_chofer', choferId)
        .isFilter('fecha_fin', null);
  }

  Future<List<Map<String, dynamic>>> myManagedLines() async {
    _requireConfig();
    final rows = await _client.rpc('my_lines');
    if (rows is! List) return [];
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> activeVehicles() async {
    _requireConfig();
    final rows = await _client.rpc('active_vehicles');
    if (rows is! List) return [];
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> choferesOfLine(int idLinea) async {
    _requireConfig();
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

    final choferesRows = await _client
        .from('chofer')
        .select('id_chofer, id_persona, licencia, foto_url, activo')
        .inFilter('id_chofer', choferIds.toList());

    final personaIds = choferesRows
        .map((c) => c['id_persona'])
        .whereType<int>()
        .toSet();
    final personasRows = personaIds.isEmpty
        ? []
        : await _client
            .from('persona')
            .select('id_persona, nombre, ci, telefono')
            .inFilter('id_persona', personaIds.toList());

    final personaById = <int, Map<String, dynamic>>{
      for (final p in personasRows)
        if (p['id_persona'] is int)
          p['id_persona'] as int: Map<String, dynamic>.from(p),
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
        if (p['id_persona'] is int)
          p['id_persona'] as int: Map<String, dynamic>.from(p),
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

  Future<void> createFine({
    required int choferId,
    required String motivo,
    required double monto,
  }) async {
    _requireConfig();
    final controlId = await _myControlId();
    if (controlId == null) return;
    await _client.from('multa').insert({
      'id_chofer': choferId,
      'id_control': controlId,
      'motivo': motivo,
      'monto': monto,
      'fecha_hora': DateTime.now().toUtc().toIso8601String(),
      'estado': 'pendiente',
    });
  }

  Future<void> setFineStatus(int fineId, String estado) async {
    _requireConfig();
    await _client
        .from('multa')
        .update({
          'estado': estado,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id_multa', fineId);
  }

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

  Stream<List<Map<String, dynamic>>> watchActiveVehicles() {
    _requireConfig();
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> refresh() async {
      try {
        final rows = await _client
            .from('vehiculo')
            .select(
                'id_vehiculo, placa, latitud, longitud, id_chofer, id_linea, activo')
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

  Future<AppRole> currentRole() async {
    _requireConfig();
    final v = await _client.rpc('my_role');
    final s = v is String ? v : v.toString();
    return roleFromString(s);
  }
}
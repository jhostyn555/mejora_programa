import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';

/// Servicio del panel administrativo adaptado al esquema REAL de Supabase:
///
///  * `public.linea`       (id_linea, nombre_linea, descripcion, activo)
///  * `public.profiles`    (id, full_name, role, requested_role)
///  * `public.list_users()` RPC que devuelve id, full_name, email, role
///
/// No se crean tablas nuevas. No se usan `lineas` ni `usuario_linea`.
class AdminService {
  SupabaseClient get _client => Supabase.instance.client;
  final AuthService _auth = AuthService();

  // -------------------------------------------------------------------------
  // Usuarios
  // -------------------------------------------------------------------------

  /// Busca usuarios por nombre, correo o rol. Incluye las cuentas que se
  /// registraron desde la app, porque `list_users()` lee de `auth.users`
  /// combinada con `public.profiles`.
  Future<List<Map<String, dynamic>>> searchUsers({String? query}) async {
    final users = await _auth.listUsers();
    final q = (query ?? '').trim().toLowerCase();
    return users
        .where((u) {
          if (q.isEmpty) return true;
          return u.fullName.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q) ||
              u.role.name.toLowerCase().contains(q);
        })
        .map((u) => {
              'id': u.id,
              'email': u.email,
              'full_name': u.fullName,
              'role': u.role.name,
              'requested_role': null,
            })
        .toList();
  }

  /// Usuarios con una solicitud de rol pendiente (`requested_role != null`).
  Future<List<Map<String, dynamic>>> pendingRequests() async {
    final profiles = await _auth.pendingRequests();
    return profiles
        .map((p) => {
              'id': p.id,
              'email': '',
              'full_name': p.fullName,
              'role': p.role.name,
              'requested_role': p.requestedRole?.name,
            })
        .toList();
  }

  /// Cambia el rol de un usuario (llama a la RPC `admin_set_role`).
  Future<void> setUserRole(String userId, AppRole newRole) async {
    await _auth.adminSetRole(userId, newRole);
  }

  /// Aprueba o rechaza una solicitud de rol pendiente.
  Future<void> decideRequest(String userId, bool approve) async {
    await _auth.decideRequest(userId, approve: approve);
  }

  // -------------------------------------------------------------------------
  // Líneas — tabla real: public.linea
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getLineas() async {
    final res = await _client
        .from('linea')
        .select('id_linea, nombre_linea, descripcion, activo, created_at')
        .order('nombre_linea');
    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> createLinea({
    required String nombre,
    String? descripcion,
  }) async {
    await _client.from('linea').insert({
      'nombre_linea': nombre.trim(),
      'descripcion': descripcion?.trim(),
      'activo': true,
    });
  }

  Future<void> updateLinea(
    int id, {
    String? nombre,
    String? descripcion,
    bool? activo,
  }) async {
    final updates = <String, dynamic>{};
    if (nombre != null) updates['nombre_linea'] = nombre.trim();
    if (descripcion != null) updates['descripcion'] = descripcion.trim();
    if (activo != null) updates['activo'] = activo;
    if (updates.isEmpty) return;
    await _client.from('linea').update(updates).eq('id_linea', id);
  }

  Future<void> deleteLinea(int id) async {
    await _client.from('linea').delete().eq('id_linea', id);
  }
}

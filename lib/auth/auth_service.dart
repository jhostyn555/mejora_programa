import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Roles de la aplicación.
///
/// `chofer` es el rol del conductor (antes llamado `transportista`; el enum
/// de la base de datos se renombró en `chofer_control_migration.sql`).
/// `roleFromString` acepta `'transportista'` por compatibilidad con perfiles
/// que no se hayan migrado todavía.
enum AppRole { cliente, chofer, control, admin }

AppRole roleFromString(String? value) {
  switch (value) {
    case 'chofer':
    case 'transportista': // compatibilidad hacia atrás
      return AppRole.chofer;
    case 'control':
      return AppRole.control;
    case 'admin':
      return AppRole.admin;
    case 'cliente':
    default:
      return AppRole.cliente;
  }
}

/// Nombre canónico que se guarda en la base de datos.
String roleToDb(AppRole role) {
  switch (role) {
    case AppRole.chofer:
      return 'chofer';
    case AppRole.control:
      return 'control';
    case AppRole.admin:
      return 'admin';
    case AppRole.cliente:
      return 'cliente';
  }
}

class Profile {
  final String id;
  final String fullName;
  final AppRole role;
  final AppRole? requestedRole;

  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    this.requestedRole,
  });

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        fullName: (map['full_name'] ?? '') as String,
        role: roleFromString(map['role'] as String?),
        requestedRole: map['requested_role'] == null
            ? null
            : roleFromString(map['requested_role'] as String?),
      );
}

/// Cuenta de cliente que el administrador puede transformar en control.
class ClientAccount {
  final String id;
  final String fullName;
  final String email;

  const ClientAccount({
    required this.id,
    required this.fullName,
    required this.email,
  });
}

/// Usuario del panel de roles (nunca administrador).
class ManagedUser {
  final String id;
  final String fullName;
  final String email;
  final AppRole role;

  const ManagedUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
  });
}

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  /// True sólo si las credenciales están definidas y `Supabase.initialize`
  /// terminó OK. Devolver false aquí evita que los widgets intenten leer
  /// `Supabase.instance.client` (que lanzaría StateError) en una app sin
  /// configurar o donde la inicialización falló por detectar service_role.
  bool get isConfigured => isSupabaseInitialized;

  bool get isSignedIn => isConfigured && _client.auth.currentSession != null;

  /// Stream seguro: es null si Supabase no fue inicializado, asi los widgets
  /// no intentan leer `Supabase.instance.client` en una app sin configurar.
  Stream<AuthState>? get authChanges =>
      isConfigured ? _client.auth.onAuthStateChange : null;

  User? get currentUser => isConfigured ? _client.auth.currentUser : null;

  void _requireConfig() {
    if (!isConfigured) {
      // Distingue los dos motivos para que el mensaje ayude a depurar.
      if (supabaseInitWarning != null) throw StateError(supabaseInitWarning!);
      if (!isSupabaseConfigured) throw StateError(supabaseMissingConfigMessage);
      throw StateError('Supabase no fue inicializado.');
    }
  }

  Future<void> signIn(String email, String password) async {
    _requireConfig();
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    _requireConfig();
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    await _client.auth.signOut();
  }

  /// Lee el perfil del usuario. Si el trigger de `schema.sql` no creo la fila
  /// (cuentas anteriores al trigger), se crea con `ensure_profile` y, si ese
  /// RPC aun no existe, se devuelve un perfil de cliente de emergencia para
  /// que el panel no muestre un error despues de iniciar sesion.
  Future<Profile?> fetchProfile() async {
    _requireConfig();
    final uid = currentUser?.id;
    if (uid == null) return null;

    Map<String, dynamic>? row;
    try {
      row = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row == null) {
        final created = await _client.rpc('ensure_profile');
        if (created is Map) row = Map<String, dynamic>.from(created);
      }
    } catch (_) {
      // Perfil ausente o RPC no aplicado: se usa el fallback de abajo.
    }

    if (row != null) return Profile.fromMap(row);

    return Profile(
      id: uid,
      fullName: (currentUser?.userMetadata?['full_name'] ?? '') as String,
      role: AppRole.cliente,
    );
  }

  /// El usuario pide ser chofer o control. Su rol no cambia hasta que
  /// un administrador o control lo apruebe.
  Future<void> requestRole(AppRole role) async {
    _requireConfig();
    if (role != AppRole.chofer && role != AppRole.control) {
      throw ArgumentError('Solo se puede solicitar chofer o control');
    }
    await _client
        .from('profiles')
        .update({'requested_role': roleToDb(role)})
        .eq('id', currentUser!.id);
  }

  Future<List<Profile>> pendingRequests() async {
    _requireConfig();
    final rows = await _client
        .from('profiles')
        .select()
        .not('requested_role', 'is', null);
    return (rows as List)
        .map((r) => Profile.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> decideRequest(String userId, {required bool approve}) async {
    _requireConfig();
    await _client.rpc(
      'decide_request',
      params: {'target': userId, 'approve': approve},
    );
  }

  /// Clientes existentes que el admin puede promover a control.
  Future<List<ClientAccount>> listClients() async {
    _requireConfig();
    final rows = await _client.rpc('list_clients');
    return (rows as List)
        .map(
          (r) => ClientAccount(
            id: r['id'] as String,
            fullName: (r['full_name'] ?? '') as String,
            email: (r['email'] ?? '') as String,
          ),
        )
        .toList();
  }

  /// Transforma una cuenta de cliente en control (solo admin en el backend).
  Future<void> promoteToControl(String userId) async {
    _requireConfig();
    await _client.rpc(
      'promote_to_control',
      params: {'target': userId},
    );
  }

  /// Usuarios no administradores del panel de roles.
  Future<List<ManagedUser>> listUsers() async {
    _requireConfig();
    final rows = await _client.rpc('list_users');
    return (rows as List)
        .map(
          (r) => ManagedUser(
            id: r['id'] as String,
            fullName: (r['full_name'] ?? '') as String,
            email: (r['email'] ?? '') as String,
            role: roleFromString(r['role'] as String?),
          ),
        )
        .toList();
  }

  /// Asigna cliente/chofer/control. El backend rechaza 'admin'.
  Future<void> adminSetRole(String userId, AppRole role) async {
    _requireConfig();
    await _client.rpc(
      'admin_set_role',
      params: {'target': userId, 'new_role': roleToDb(role)},
    );
  }
}

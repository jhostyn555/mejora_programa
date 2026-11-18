import 'package:supabase_flutter/supabase_flutter.dart';

/// Credenciales públicas de Supabase. Se inyectan al compilar/ejecutar:
///
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=TU_PUBLISHABLE_KEY
///
/// Cuando no estan definidas la app sigue funcionando como planificador de
/// rutas; solo se desactivan el inicio de sesion y el panel de cuenta.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// True cuando las constantes de compilación están definidas (no vacías).
/// No garantiza que `Supabase.initialize` se haya llamado — para eso usa
/// [isSupabaseInitialized] en código que accede a `Supabase.instance.client`.
bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

const supabaseMissingConfigMessage =
    'Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY (dart-define).';

/// Flag en tiempo de ejecución: true si `Supabase.initialize` se llamó y
/// terminó sin errores. Lo pone `initializeSupabase()` abajo.
bool _isSupabaseInitialized = false;
bool get isSupabaseInitialized => _isSupabaseInitialized;

/// Detecta si alguien puso por error la service_role key en el cliente.
/// La service_role key es PRIVADA y salta toda la RLS: usarla en la app
/// supondría un agujero de seguridad grave.
bool get _looksLikeSecretKey {
  if (!isSupabaseConfigured) return false;
  final k = supabasePublishableKey;
  // Formato nuevo de Supabase: las service_role keys empiezan con "sb_secret_"
  // y las publishable/anon keys con "sb_publishable_". Los JWT legacy
  // (eyJ...) son más difíciles de distinguir sin decodificarlos; el caso más
  // común es la cadena plana sb_secret_, que es la que el dashboard muestra
  // como "service_role".
  return k.startsWith('sb_secret_') || k.contains('service_role');
}

/// Mensaje que las vistas muestran cuando se detectó la service_role key.
const _serviceRoleWarning =
    'Se detectó la service_role key (sb_secret_...) en SUPABASE_ANON_KEY. '
    'ESA KEY ES PRIVADA: nunca la pongas en el cliente Flutter. Usa la '
    'publishable/anon key (Project Settings → API → Project API keys → '
    'anon public). Mientras tanto la app se niega a inicializar Supabase.';

/// Inicializa Supabase solo cuando hay credenciales y NO se detectó la
/// service_role key. Evita que la app completa se caiga en el arranque si
/// el planificador se usa sin autenticacion.
Future<void> initializeSupabase() async {
  if (!isSupabaseConfigured) return;
  if (_looksLikeSecretKey) {
    // Fallar a propósito con un mensaje claro en vez de exponer el agujero.
    throw StateError(_serviceRoleWarning);
  }
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  _isSupabaseInitialized = true;
}

/// Para que AuthGate / LoggedOutPage puedan mostrar el aviso cuando la
/// inicialización se negó por usar service_role.
String? get supabaseInitWarning =>
    _looksLikeSecretKey ? _serviceRoleWarning : null;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Credenciales publicas de Supabase. Se inyectan al compilar/ejecutar:
///
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=TU_PUBLISHABLE_KEY
///
/// Cuando no estan definidas la app sigue funcionando como planificador de
/// rutas; solo se desactivan el inicio de sesion y el panel de cuenta.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

const supabaseMissingConfigMessage =
    'Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY (dart-define).';

/// Inicializa Supabase solo cuando hay credenciales. Evita que la app completa
/// se caiga en el arranque si el planificador se usa sin autenticacion.
Future<void> initializeSupabase() async {
  if (!isSupabaseConfigured) return;
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
}

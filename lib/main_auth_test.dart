import 'package:flutter/material.dart';

import 'auth/auth_gate.dart';
import 'auth/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSupabase();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AuthGate(),
  ));
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Servicio para subir imágenes a Cloudinary usando multipart/form-data.
///
/// Requiere que las variables de entorno estén definidas (en .env local o vía
/// --dart-define al compilar):
///   - CLOUDINARY_CLOUD_NAME   (ej. h9z1zfeg)
///   - CLOUDINARY_UPLOAD_PRESET (ej. trufi_app_trabajo_grupal)
///
/// Flujo:
///   1. [pickImage]       → elige una foto de galería/cámara (opcional).
///   2. [uploadImage]     → envía el archivo a Cloudinary y devuelve la
///                          secure_url (lista para guardar en Supabase).
class CloudinaryService {
  CloudinaryService._();

  static final CloudinaryService instance = CloudinaryService._();

  /// Carga el archivo .env. Llamar una vez al inicio de la app (main).
  static Future<void> loadEnv() async {
    await dotenv.load(fileName: '.env');
  }

  String get _cloudName => dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
  String get _uploadPreset => dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '';

  /// Endpoint de subida de Cloudinary.
  Uri get _uploadUri =>
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/upload');

  /// Valida que las variables de entorno estén configuradas.
  void _requireConfig() {
    if (_cloudName.isEmpty) {
      throw StateError(
        'Falta CLOUDINARY_CLOUD_NAME en las variables de entorno (.env o --dart-define).',
      );
    }
    if (_uploadPreset.isEmpty) {
      throw StateError(
        'Falta CLOUDINARY_UPLOAD_PRESET en las variables de entorno (.env o --dart-define).',
      );
    }
  }

  /// Sube un archivo de imagen a Cloudinary y devuelve la [secure_url].
  ///
  *Lanza [StateError] si faltan las variables de entorno o si la subida falla.*
  Future<String> uploadImage(File imageFile) async {
    _requireConfig();

    final request = http.MultipartRequest('POST', _uploadUri)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        if (secureUrl == null || secureUrl.isEmpty) {
          throw StateError(
            'Cloudinary respondió OK pero no devolvió secure_url.',
          );
        }
        return secureUrl;
      } else {
        throw StateError(
          'Error al subir a Cloudinary (${response.statusCode}): ${response.body}',
        );
      }
    } on SocketException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (e) {
      throw StateError('No se pudo subir la imagen a Cloudinary: $e');
    }
  }

  /// Sube los bytes de una imagen a Cloudinary y devuelve la [secure_url].
  Future<String> uploadImageBytes({
    required List<int> bytes,
    required String filename,
  }) async {
    _requireConfig();

    final request = http.MultipartRequest('POST', _uploadUri)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        if (secureUrl == null || secureUrl.isEmpty) {
          throw StateError(
            'Cloudinary respondió OK pero no devolvió secure_url.',
          );
        }
        return secureUrl;
      } else {
        throw StateError(
          'Error al subir a Cloudinary (${response.statusCode}): ${response.body}',
        );
      }
    } on SocketException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (e) {
      throw StateError('No se pudo subir la imagen a Cloudinary: $e');
    }
  }

  /// Abre el selector de imágenes de [image_picker] y devuelve el [File]
  /// elegido, o `null` si el usuario canceló.
  ///
  *Source: [ImageSource.gallery] por defecto; usa [ImageSource.camera] para cámara.*
  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return null;
    return File(picked.path);
  }
}

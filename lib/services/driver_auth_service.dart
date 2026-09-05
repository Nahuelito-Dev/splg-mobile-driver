import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/core/network/api_client.dart';

/// Autenticación real del chofer.
///
/// Flujo (igual que la app cliente): (1) Firebase valida email+password,
/// (2) traemos el perfil desde el backend por email para obtener el `user_id`
/// REAL de la base — que es el id que usan el radar (GEO) y los eventos de
/// socket del chofer (`driver:join` / `driver:update-location`), NO el uid de
/// Firebase. Guardamos ese id + datos básicos para el resto de la operación.
class DriverAuthService with ListenableServiceMixin {
  DriverAuthService() {
    listenToReactiveValues([_userId, _fullName, _email]);
  }

  final _firebaseAuth = FirebaseAuth.instance;
  final _apiClient = ApiClient();
  final _storage = const FlutterSecureStorage();

  static const _kUserId = 'driver_user_id';
  static const _kFullName = 'driver_full_name';
  static const _kEmail = 'driver_email';

  final ReactiveValue<String?> _userId = ReactiveValue<String?>(null);
  final ReactiveValue<String?> _fullName = ReactiveValue<String?>(null);
  final ReactiveValue<String?> _email = ReactiveValue<String?>(null);

  /// user_id de la base (User PK) del chofer logueado. Es lo que consume el
  /// backend para el GEO y el socket. Null si no hay sesión.
  String? get userId => _userId.value;
  String? get fullName => _fullName.value;
  String? get email => _email.value;

  bool get isLoggedIn => _firebaseAuth.currentUser != null && userId != null;

  /// Token de Firebase (JWT) para el handshake del socket y los headers REST.
  Future<String?> get token async =>
      await _firebaseAuth.currentUser?.getIdToken();

  /// Inicia sesión. Devuelve true si Firebase autenticó Y pudimos resolver el
  /// perfil del chofer (user_id). Si el perfil no es un chofer o no se puede
  /// traer, cerramos la sesión y devolvemos false.
  Future<bool> signIn(String email, String password) async {
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final resolved = await _loadProfile(email.trim());
      if (resolved) return true;

      await _firebaseAuth.signOut();
      return false;
    } on FirebaseAuthException catch (e) {
      log('Firebase sign in falló: ${e.code}', name: 'DriverAuthService');
      return false;
    } catch (e) {
      log('Error en signIn: $e', name: 'DriverAuthService');
      await _firebaseAuth.signOut();
      return false;
    }
  }

  /// Trae el perfil por email y guarda el user_id. Valida que el rol sea
  /// `delivery` (un cliente no debería entrar a la app del chofer).
  Future<bool> _loadProfile(String email) async {
    try {
      final tk = await token;
      final response = await _apiClient.get('users/email/$email', tk);
      if (response.statusCode != 200) return false;

      final data = response.data;
      if (data is! Map) return false;

      final id = data['user_id']?.toString();
      final roleType = (data['role'] is Map)
          ? data['role']['type']?.toString()
          : data['role']?.toString();

      if (id == null || id.isEmpty) return false;
      if (roleType != 'delivery' && roleType != 'super_admin') {
        log('Rol no autorizado para app chofer: $roleType',
            name: 'DriverAuthService');
        return false;
      }

      final fullName = data['full_name']?.toString();
      _userId.value = id;
      _fullName.value = fullName;
      _email.value = email;

      // Persistimos para restaurar la sesión en el próximo arranque sin
      // re-loguear (Firebase ya persiste su sesión; nos faltaba el user_id).
      await _storage.write(key: _kUserId, value: id);
      await _storage.write(key: _kEmail, value: email);
      if (fullName != null) {
        await _storage.write(key: _kFullName, value: fullName);
      }
      return true;
    } catch (e) {
      log('Error trayendo perfil: $e', name: 'DriverAuthService');
      return false;
    }
  }

  /// Restaura la sesión al arrancar la app: si Firebase tiene una sesión activa
  /// y guardamos el user_id, repuebla los datos SIN pedir login de nuevo. Si el
  /// user_id no está en storage (edge), lo re-trae del backend. Devuelve true si
  /// quedó una sesión de chofer válida.
  Future<bool> restoreSession() async {
    try {
      if (_firebaseAuth.currentUser == null) return false;

      final storedId = await _storage.read(key: _kUserId);
      if (storedId != null && storedId.isNotEmpty) {
        _userId.value = storedId;
        _fullName.value = await _storage.read(key: _kFullName);
        _email.value = await _storage.read(key: _kEmail);
        return true;
      }

      // Fallback: hay sesión Firebase pero perdimos el user_id → re-traer perfil.
      final email = _firebaseAuth.currentUser?.email;
      if (email == null) return false;
      return await _loadProfile(email);
    } catch (e) {
      log('Error restaurando sesión: $e', name: 'DriverAuthService');
      return false;
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    _userId.value = null;
    _fullName.value = null;
    _email.value = null;
    await _storage.deleteAll();
  }
}

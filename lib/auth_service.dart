import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class AuthService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyUserId = 'user_id';
  static const String _keyEmail = 'email';
  static const String _keyUsername = 'username';

  // Hash password dengan SHA-256
  static String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  static Future<void> _saveSession({
    required String userId,
    required String email,
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyUsername, username);
  }

  static String _generateUsernameFromName(String? name, String? email) {
    if (name != null && name.trim().isNotEmpty) {
      final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normalized.isNotEmpty) return normalized;
    }
    if (email != null && email.contains('@')) {
      return email.split('@').first.toLowerCase();
    }
    return 'user${DateTime.now().millisecondsSinceEpoch}';
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> _ensureUserDocument(User firebaseUser) async {
    final docRef = _firestore.collection('users').doc(firebaseUser.uid);
    final doc = await docRef.get();
    final normalizedEmail = firebaseUser.email?.trim().toLowerCase() ?? '';
    final username = _generateUsernameFromName(firebaseUser.displayName, firebaseUser.email);

    if (!doc.exists) {
      await docRef.set({
        'email': normalizedEmail,
        'username': username,
        'fullName': firebaseUser.displayName ?? '',
        'isActive': true,
        'authProvider': 'google',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });
    } else {
      await docRef.update({
        'lastLogin': FieldValue.serverTimestamp(),
        'authProvider': doc.data()?['authProvider'] ?? 'google',
      });
    }

    return await docRef.get();
  }

  // Check jika user sudah login
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
    final userId = prefs.getString(_keyUserId);
    
    if (isLoggedIn && userId != null) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          return true;
        }
      } catch (_) {}
    }
    
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null) {
      final userDoc = await _ensureUserDocument(firebaseUser);
      final username = userDoc.data()?['username'] ?? _generateUsernameFromName(firebaseUser.displayName, firebaseUser.email);
      await _saveSession(
        userId: firebaseUser.uid,
        email: firebaseUser.email?.trim().toLowerCase() ?? '',
        username: username,
      );
      return true;
    }
    
    return false;
  }

  // Login dengan email dan password (Custom dengan Firestore)
  static Future<AuthResult> login(String email, String password) async {
    try {
      final hashedPassword = _hashPassword(password);
      
      // Cari user di Firestore berdasarkan email
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return AuthResult(success: false, errorMessage: 'Email tidak terdaftar');
      }

      final userDoc = querySnapshot.docs.first;
      final userData = userDoc.data();

      // Verify password
      if (userData['password'] != hashedPassword) {
        return AuthResult(success: false, errorMessage: 'Password salah');
      }

      // Check if user is active
      if (userData['isActive'] == false) {
        return AuthResult(success: false, errorMessage: 'Akun ini telah dinonaktifkan');
      }

      // Update last login
      await userDoc.reference.update({
        'lastLogin': FieldValue.serverTimestamp(),
        'authProvider': 'email',
      });

      // Simpan session
      await _saveSession(
        userId: userDoc.id,
        email: email.trim().toLowerCase(),
        username: userData['username'] ?? '',
      );
      
      return AuthResult(
        success: true,
        userId: userDoc.id,
        username: userData['username'] ?? '',
      );
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Error: $e');
    }
  }
  
  static Future<AuthResult> loginWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return AuthResult(success: false, errorMessage: 'Login Google dibatalkan');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) {
        return AuthResult(success: false, errorMessage: 'User Google tidak ditemukan');
      }

      final userDoc = await _ensureUserDocument(user);
      final username = userDoc.data()?['username'] ?? _generateUsernameFromName(user.displayName, user.email);

      await _saveSession(
        userId: user.uid,
        email: user.email?.trim().toLowerCase() ?? '',
        username: username,
      );

      return AuthResult(
        success: true,
        userId: user.uid,
        username: username,
      );
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Login Google gagal: $e');
    }
  }

  // Register user baru
  static Future<AuthResult> register(
    String email,
    String password,
    String username,
    String fullName,
  ) async {
    try {
      // Validasi input
      if (email.trim().isEmpty || password.isEmpty || username.trim().isEmpty) {
        return AuthResult(success: false, errorMessage: 'Semua field harus diisi');
      }

      if (password.length < 6) {
        return AuthResult(success: false, errorMessage: 'Password minimal 6 karakter');
      }

      // Check email sudah terdaftar
      final emailCheck = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();

      if (emailCheck.docs.isNotEmpty) {
        return AuthResult(success: false, errorMessage: 'Email sudah terdaftar');
      }

      // Check username sudah terdaftar
      final usernameCheck = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.trim().toLowerCase())
          .limit(1)
          .get();

      if (usernameCheck.docs.isNotEmpty) {
        return AuthResult(success: false, errorMessage: 'Username sudah terdaftar');
      }

      // Hash password
      final hashedPassword = _hashPassword(password);

      // Buat user baru di Firestore
      final userRef = await _firestore.collection('users').add({
        'email': email.trim().toLowerCase(),
        'username': username.trim().toLowerCase(),
        'fullName': fullName.trim(),
        'password': hashedPassword, // Hashed password
        'isActive': true,
        'authProvider': 'email',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      // Simpan session
      await _saveSession(
        userId: userRef.id,
        email: email.trim().toLowerCase(),
        username: username.trim().toLowerCase(),
      );

      return AuthResult(
        success: true,
        userId: userRef.id,
        username: username.trim(),
      );
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Error: $e');
    }
  }

  // Reset password (generate password baru dan simpan ke Firestore)
  static Future<AuthResult> resetPassword(String email) async {
    try {
      // Cari user berdasarkan email
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return AuthResult(success: false, errorMessage: 'Email tidak terdaftar');
      }

      // Generate password baru sementara (8 karakter random)
      final newPassword = _generateRandomPassword(8);
      final hashedPassword = _hashPassword(newPassword);

      // Update password di Firestore
      await querySnapshot.docs.first.reference.update({
        'password': hashedPassword,
        'passwordResetAt': FieldValue.serverTimestamp(),
      });

      // Simpan password reset request di Firestore untuk ditampilkan di admin panel
      await _firestore.collection('password_resets').add({
        'email': email.trim().toLowerCase(),
        'newPassword': newPassword, // Plain text untuk ditampilkan
        'requestedAt': FieldValue.serverTimestamp(),
        'isUsed': false,
      });

      return AuthResult(
        success: true,
        errorMessage: 'Password berhasil direset.\n\nPassword baru: $newPassword\n\n⚠️ Catat password ini dengan aman!',
      );
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Error: $e');
    }
  }

  // Change password (untuk user yang sudah login)
  static Future<AuthResult> changePassword(String oldPassword, String newPassword) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_keyUserId);

      if (userId == null) {
        return AuthResult(success: false, errorMessage: 'Anda harus login terlebih dahulu');
      }

      if (newPassword.length < 6) {
        return AuthResult(success: false, errorMessage: 'Password baru minimal 6 karakter');
      }

      // Get user data
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return AuthResult(success: false, errorMessage: 'User tidak ditemukan');
      }

      final userData = userDoc.data()!;

      // Verify old password
      if (userData['password'] != _hashPassword(oldPassword)) {
        return AuthResult(success: false, errorMessage: 'Password lama salah');
      }

      // Update password
      await userDoc.reference.update({
        'password': _hashPassword(newPassword),
        'passwordChangedAt': FieldValue.serverTimestamp(),
      });

      return AuthResult(success: true, errorMessage: 'Password berhasil diubah');
    } catch (e) {
      return AuthResult(success: false, errorMessage: 'Error: $e');
    }
  }

  // Generate random password
  static String _generateRandomPassword(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(chars[(random + i) % chars.length]);
    }
    return buffer.toString();
  }

  // Logout
  static Future<void> logout() async {
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}
    
    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyUsername);
  }

  // Get current user info
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyUserId);

    if (userId == null) {
      return null;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return null;
      }

      final userData = userDoc.data()!;
      return {
        'userId': userId,
        'email': userData['email'],
        'username': userData['username'],
        'fullName': userData['fullName'] ?? '',
        'createdAt': userData['createdAt'],
        'lastLogin': userData['lastLogin'],
      };
    } catch (e) {
      return null;
    }
  }

  // Get username yang sedang login
  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  // Get user ID yang sedang login
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }
}

// Result class untuk handle login/register result
class AuthResult {
  final bool success;
  final String? errorMessage;
  final String? userId;
  final String? username;

  AuthResult({
    required this.success,
    this.errorMessage,
    this.userId,
    this.username,
  });
}

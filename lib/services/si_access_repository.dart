import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Reads the established Firebase role sources without granting a role on the
/// client. Firestore rules remain the enforcement point for every data query.
class SiAccessRepository {
  SiAccessRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<bool> isSystemIntegrator(User user) async {
    late final IdTokenResult token;
    try {
      // Refresh exactly once before examining custom claims so a recently
      // granted SI role is not routed through the normal U-Link flow.
      token = await user.getIdTokenResult(true);
    } catch (error) {
      throw SiRoleLookupException(
        'Unable to refresh the signed-in user role.',
        error,
      );
    }
    final claims = token.claims ?? const <String, dynamic>{};
    if (SiRolePolicy.isCustomClaimSystemIntegratorRole(claims['role'])) {
      return true;
    }

    // Legacy installations retain this value in users/{uid}. A profile read
    // failure is a real authorization/setup error, not evidence of a normal
    // user, so callers must present it instead of taking the normal route.
    DocumentSnapshot<Map<String, dynamic>> profile;
    try {
      profile = await _firestore.collection('users').doc(user.uid).get();
    } catch (error) {
      throw SiRoleLookupException(
        'Unable to read the System Integrator profile.',
        error,
      );
    }
    final data = profile.data();
    if (data == null) return false;
    return SiRolePolicy.isLegacyProfileSystemIntegratorRole(data['role']);
  }
}

class SiRoleLookupException implements Exception {
  const SiRoleLookupException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Shared pure role policy for Firebase custom claims and the legacy profile.
class SiRolePolicy {
  const SiRolePolicy._();

  static bool isCustomClaimSystemIntegratorRole(Object? value) {
    final role = _normalized(value);
    return role == 'si' || role == 'system_integrator';
  }

  static bool isLegacyProfileSystemIntegratorRole(Object? value) {
    final role = _normalized(value);
    return role == 'si' ||
        role == 'system_integrator' ||
        role == 'system integrator';
  }

  static String? _normalized(Object? value) {
    if (value is! String) return null;
    return value.trim().toLowerCase();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Reads the established Firebase role sources without granting a role on the
/// client. Firestore rules remain the enforcement point for every data query.
class SiAccessRepository {
  SiAccessRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<bool> isSystemIntegrator(User user) async {
    final token = await user.getIdTokenResult(true);
    final claims = token.claims ?? const <String, dynamic>{};
    if (claims['role'] == 'si' ||
        claims['role'] == 'system_integrator' ||
        claims['systemIntegrator'] == true) {
      return true;
    }

    // Legacy installations can retain role information in users/{uid}. This
    // is only a navigation hint; deployed rules must independently require an
    // SI custom claim before returning provisioning records.
    DocumentSnapshot<Map<String, dynamic>> profile;
    try {
      profile = await _firestore.collection('users').doc(user.uid).get();
    } catch (_) {
      // A normal user may not have permission to read an SI profile document.
      return false;
    }
    final data = profile.data();
    if (data == null) return false;
    final role = data['role'];
    final roles = data['roles'];
    return role == 'si' ||
        role == 'system_integrator' ||
        data['systemIntegrator'] == true ||
        (roles is List &&
            roles.any((item) => item == 'si' || item == 'system_integrator'));
  }
}

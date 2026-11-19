import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/services/provisioning_repository.dart';

void main() {
  test('company fetch always requests Firestore server data', () async {
    GetOptions? receivedOptions;

    final value = await fetchCompaniesFromServer((options) async {
      receivedOptions = options;
      return 'server-result';
    });

    expect(value, 'server-result');
    expect(receivedOptions!.source, Source.server);
  });

  test('company server fetch surfaces a friendly network error', () async {
    await expectLater(
      fetchCompaniesFromServer<String>(
        (_) => Future<String>.error(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.message,
          'message',
          'Could not reach the server to load your assigned companies. '
              'Check your connection and try again.',
        ),
      ),
    );
  });
}

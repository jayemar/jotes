import 'dart:io' show HandshakeException, OSError;
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/providers/sync_provider.dart';
import 'package:pocketbase/pocketbase.dart';

/// Unlike sync_provider_test.dart (tagged 'integration' - it exercises
/// SyncNotifier.connect against a real PocketBase instance), this only
/// covers describeConnectError's pure string logic, so it needs neither a
/// live server nor mocked platform channels.
void main() {
  test('a TLS handshake failure against a plain-HTTP server gets a clear, '
      'actionable message instead of the raw exception dump', () {
    final error = ClientException(
      originalError: HandshakeException(
        'Handshake error in client',
        OSError('WRONG_VERSION_NUMBER(tls_record.cc:127)'),
      ),
    );

    expect(describeConnectError(error), contains('http://'));
  });

  test('a handshake failure for an unrelated reason keeps the raw exception '
      'text, since the http-vs-https diagnosis would be wrong', () {
    final error = ClientException(
      originalError: HandshakeException(
        'Handshake error in client',
        OSError('CERTIFICATE_VERIFY_FAILED'),
      ),
    );

    expect(describeConnectError(error), error.toString());
  });

  test('any other error type falls back to its own toString()', () {
    final error = ClientException(statusCode: 400);

    expect(describeConnectError(error), error.toString());
  });
}

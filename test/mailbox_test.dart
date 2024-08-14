// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:native_synchronization_temp/mailbox.dart';
import 'package:native_synchronization_temp/sendable.dart';
import 'package:test/test.dart';

final Logger _logger = Logger('Testing');

void main() {
  Future<String> startHelperIsolate(Sendable<Mailbox> sendableMailbox) async {
    _logger.fine(() => 'starting isolate');
    return Isolate.run(debugName: 'Postman', () {
      _logger.fine(() => 'Isolate: started');
      sleep(const Duration(milliseconds: 3000));
      _logger.fine(() => 'Isolate: calling put');
      sendableMailbox.materialize().put(Uint8List(42)..[41] = 42);
      _logger.fine(() => 'Isolate: returned from put');
      return 'success';
    });
  }

  test('mailbox', () async {
    final mailbox = Mailbox();
    final helperResult = startHelperIsolate(mailbox.asSendable);
    final value = mailbox.take();
    expect(value, isA<Uint8List>());
    expect(value.length, equals(42));
    expect(value[41], equals(42));
    expect(await helperResult, equals('success'));
  });

///////////////////////////////////////////////////////////////////////
  ///
  /// Causing crash
  ///
///////////////////////////////////////
  test('mailbox - timeout', () async {
    final mailbox = Mailbox();
    final helperResult = startHelperIsolate(mailbox.asSendable);
    // expect(mailbox.take, throwsA(isA<TimeoutException>()));
    // expect(() => mailbox.take(timeout: const Duration(seconds: 2)),
    //     throwsA(isA<TimeoutException>()));
    await Future.delayed(const Duration(seconds: 5), () {});
    _logger.fine(() => 'reenteriing mailbox.take');
    final value = mailbox.take(timeout: const Duration(seconds: 2));
    // final value = mailbox.take();
    expect(value, isA<Uint8List>());
    expect(value.length, equals(42));
    expect(value[41], equals(42));
    expect(await helperResult, equals('success'));
  });

  Future<String> startHelperIsolateClose(
          Sendable<Mailbox> sendableMailbox) async =>
      Isolate.run(() {
        sleep(const Duration(milliseconds: 500));
        final mailbox = sendableMailbox.materialize();
        try {
          mailbox.take();
        } catch (_) {
          return 'success';
        }
        return 'failed';
      });

  test('mailbox close', () async {
    final mailbox = Mailbox();
    mailbox.put(Uint8List(42)..[41] = 42);
    mailbox.close();
    final helperResult = startHelperIsolateClose(mailbox.asSendable);
    expect(await helperResult, equals('success'));
  });
}

// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:native_synchronization/primitives.dart';
import 'package:native_synchronization/sendable.dart';
import 'package:test/test.dart';

void main() {
  group('mutex', () {
    test('simple', () {
      final mutex = Mutex();
      expect(mutex.runLocked(() => 42), equals(42));
    });

    /// Helper Isolate to test mutex locking.
    /// This Isolate will wait for the main isolate to set the value
    /// of the [ptrAddress]to 2.
    ///
    /// @param ptrAddress The address of the pointer to set to 2.
    /// @param sendableMutex The mutex to use.
    ///
    /// Returns success
    ///
    Future<String> spawnHelperIsolate(
        int ptrAddress, Sendable<Mutex> sendableMutex) {
      return Isolate.run(() {
        final ptr = Pointer<Uint8>.fromAddress(ptrAddress);
        final mutex = sendableMutex.materialize();

        while (true) {
          sleep(const Duration(milliseconds: 10));
          if (mutex.runLocked(() {
            if (ptr.value == 2) {
              return true;
            }
            ptr.value = 0;
            sleep(const Duration(milliseconds: 500));
            ptr.value = 1;
            return false;
          })) {
            break;
          }
        }

        return 'success';
      });
    }

    test('isolate', () async {
      await using((arena) async {
        final ptr = arena.allocate<Uint8>(1);
        final mutex = Mutex();

        final helperResult = spawnHelperIsolate(ptr.address, mutex.asSendable);

        while (true) {
          final sw = Stopwatch()..start();
          if (mutex.runLocked(() {
            if (sw.elapsedMilliseconds > 300 && ptr.value == 1) {
              ptr.value = 2;
              return true;
            }
            return false;
          })) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 10), () {});
        }
        expect(await helperResult, equals('success'));
      });
    });

    test('Timeout', () async {
      final mutex = Mutex();

      unawaited(
          spawnLockedMutex(mutex.asSendable, const Duration(seconds: 10)));

      /// give the isoalte a chance to start.
      sleep(const Duration(seconds: 2));

      /// force a timeout
      expect(
          () => mutex.runLocked(timeout: const Duration(seconds: 3), () {
                sleep(const Duration(milliseconds: 100));
                return true;
              }),
          throwsA(isA<TimeoutException>()));

      /// wait for the lock to be released.
      expect(
          mutex.runLocked(timeout: const Duration(seconds: 15), () {
            sleep(const Duration(milliseconds: 100));
            return true;
          }),
          isTrue);
    });
  });

  group('condvar', () {
    Future<String> spawnHelperIsolate(
        int ptrAddress,
        Sendable<Mutex> sendableMutex,
        Sendable<ConditionVariable> sendableCondVar) async {
      return Isolate.run(() {
        final ptr = Pointer<Uint8>.fromAddress(ptrAddress);
        final mutex = sendableMutex.materialize();
        final condVar = sendableCondVar.materialize();

        return mutex.runLocked(() {
          ptr.value = 1;
          while (ptr.value == 1) {
            condVar.wait(mutex);
          }
          return ptr.value == 2 ? 'success' : 'failure';
        });
      });
    }

    test('isolate', () async {
      await using((arena) async {
        final ptr = arena.allocate<Uint8>(1);
        final mutex = Mutex();
        final condVar = ConditionVariable();

        final helperResult = spawnHelperIsolate(
            ptr.address, mutex.asSendable, condVar.asSendable);

        while (true) {
          final success = mutex.runLocked(() {
            if (ptr.value == 1) {
              ptr.value = 2;
              condVar.notify();
              return true;
            }
            return false;
          });
          if (success) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 20), () {});
        }

        expect(await helperResult, equals('success'));
      });
    });
  });
}

/// Create an isolate that locks the mutex for [duration]
Future<void> spawnLockedMutex(
        Sendable<Mutex> sendableMutex, Duration duration) async =>
    Isolate.run<void>(() {
      final mutex = sendableMutex.materialize();
      log('Isolate started');

      mutex.runLocked(() {
        log('isolate spawnLockedMutext has lock');
        // await Future.delayed(duration);
        sleep(duration);
        log('isolate spawnLockedMutext returning');
        return true;
      });
      log('runLock completed');
    });

void log(String message) {
  print('${DateTime.now()}: $message');
}

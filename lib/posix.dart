// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'primitives.dart';

/// Posix timeout error number.
// ignore: constant_identifier_names
const ETIMEDOUT = 110;

class _PosixMutex extends Mutex {
  /// This is maximum value of `sizeof(pthread_mutex_t)` across all supported
  /// platforms.
  static const _sizeInBytes = 64;

  final Pointer<pthread_mutex_t> _impl;

  static final _finalizer = Finalizer<Pointer<pthread_mutex_t>>((ptr) {
    pthread_mutex_destroy(ptr);
    malloc.free(ptr);
  });

  _PosixMutex()
      : _impl = malloc.allocate(_PosixMutex._sizeInBytes),
        super._() {
    if (pthread_mutex_init(_impl, nullptr) != 0) {
      malloc.free(_impl);
      throw StateError('Failed to initialize mutex');
    }
    _finalizer.attach(this, _impl);
  }

  _PosixMutex.fromAddress(int address)
      : _impl = Pointer.fromAddress(address),
        super._();

  @override
  void _lock({Duration? timeout}) {
    if (timeout == null) {
      if (pthread_mutex_lock(_impl) != 0) {
        throw StateError('Failed to lock mutex');
      }
    } else {
      _timedLock(timeout);
    }
  }

  void _timedLock(Duration timeout) {
    var timespec = _allocateTimespec(timeout);
    final result = pthread_mutex_timedlock(_impl, timespec);
    malloc.free(timespec);

    if (result == ETIMEDOUT) {
      throw TimeoutException('Timed out waiting for Mutex lock');
    }
    if (result != 0) {
      throw StateError('Failed to lock mutex');
    }
  }

  @override
  void _unlock() {
    if (pthread_mutex_unlock(_impl) != 0) {
      throw StateError('Failed to unlock mutex');
    }
  }

  @override
  int get _address => _impl.address;
}

class _PosixConditionVariable extends ConditionVariable {
  /// This is maximum value of `sizeof(pthread_cond_t)` across all supported
  /// platforms.
  static const _sizeInBytes = 64;

  final Pointer<pthread_cond_t> _impl;

  static final _finalizer = Finalizer<Pointer<pthread_cond_t>>((ptr) {
    pthread_cond_destroy(ptr);
    malloc.free(ptr);
  });

  _PosixConditionVariable()
      : _impl = malloc.allocate(_PosixConditionVariable._sizeInBytes),
        super._() {
    if (pthread_cond_init(_impl, nullptr) != 0) {
      malloc.free(_impl);
      throw StateError('Failed to initialize condition variable');
    }
    _finalizer.attach(this, _impl);
  }

  _PosixConditionVariable.fromAddress(int address)
      : _impl = Pointer.fromAddress(address),
        super._();

  @override
  void notify() {
    if (pthread_cond_signal(_impl) != 0) {
      throw StateError('Failed to signal condition variable');
    }
  }

  @override
  void wait(covariant _PosixMutex mutex, {Duration? timeout}) {
    if (timeout == null) {
      if (pthread_cond_wait(_impl, mutex._impl) != 0) {
        throw StateError('Failed to wait on a condition variable');
      }
    } else {
      _timedWait(timeout, mutex);
    }
  }

  /// Waits on a condition variable with a timeout.
  void _timedWait(Duration timeout, _PosixMutex mutex) {
    final wakeUpTime = _allocateTimespec(timeout);
    final result = pthread_cond_timedwait(_impl, mutex._impl, wakeUpTime);

    malloc.free(wakeUpTime);

    if (result == ETIMEDOUT) {
      throw TimeoutException('Timed out waiting for conditional variable');
    }

    if (result != 0) {
      throw StateError('Failed to wait on a condition variable');
    }
  }

  @override
  int get _address => _impl.address;
}

/// Create a posix timespec from a [timeout].
/// The returned [pthread_timespec_t] must be freed by a call
/// to [malloc.free]
Pointer<pthread_timespec_t> _allocateTimespec(Duration timeout) {
  final timespec =
      malloc.allocate<pthread_timespec_t>(sizeOf<pthread_timespec_t>());

  /// calculate the absolute timeout in microseconds
  final microSecondsSinceEpoc = DateTime.now().microsecondsSinceEpoch;
  final wakupTime = microSecondsSinceEpoc + timeout.inMicroseconds;

  /// seconds since the epoc to wait until.
  timespec.ref.tv_sec = wakupTime ~/ 1000000;

  /// additional nano-seconds after tv_sec to wait
  timespec.ref.tv_nsec = (wakupTime % 1000000) * 1000;
  return timespec;
}

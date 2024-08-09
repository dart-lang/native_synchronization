# 0.4.0
- Added a timeout to the Mailbox.take, Mutex.runLocked and ConditionVariable.wait methods.
 Note: the Mutex timeout is ignored on Windows.


## 0.3.0
- Add a closed state to `Mailbox`.

## 0.2.0

- Lower SDK lower bound to 3.0.0.

## 0.1.0

- Initial version.
- Expose `Mutex` and `ConditionVariable`
- Implement `Mailbox`.

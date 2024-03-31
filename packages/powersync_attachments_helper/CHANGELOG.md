## 0.3.0

- BREAKING CHANGE: `reconcileId` has been removed in favour of `reconcileIds`. This will require a change to `watchIds` implementation which is shown in `example/getting_started.dart`
-

## 0.2.1

- Added `onUploadError` as an optional function that can be set when setting up the queue to handle upload errors
- Added `onDownloadError` as an optional function that can be set when setting up the queue to handle upload errors

## 0.2.0

- Potentially BREAKING CHANGE for users who rely on multiple attachment queues.
  Moved away from randomly generating queue table name in favour of  a user creating a queue and table using a name of their choosing.

## 0.1.5

- Allow different file extensions besides jpg.

## 0.1.4

- Update dependencies.
- Declare linux, macos and windows platform support.

## 0.1.3

- Update README.

## 0.1.2

- Update example.

## 0.1.1

- Amend pubspec.yml repository to correct url and use flutter sdk as dependency.

## 0.1.0

- Initial version.

## 0.6.1

 - Update a dependency to the latest release.

## 0.6.0

- Update a dependency to the latest release.

## 0.6.0-alpha.1

- Update a dependency to the latest release.

## 0.5.1

- Upgrade `sqlite_async` to version 0.8.1.

## 0.5.0

- Upgrade minimum Dart SDK constraint to `3.4.0`.
- Upgrade `sqlite_async` to version 0.7.0.

## 0.3.0-alpha.4

- Update a dependency to the latest release.

## 0.3.0-alpha.3

- Update a dependency to the latest release.

## 0.3.0-alpha.2

> Note: This release has breaking changes.

- **FIX**: reset isProcessing when exception is thrown during sync process. (#81).
- **FIX**: attachment queue duplicating requests (#68).
- **FIX**(powersync-attachements-helper): pubspec file (#29).
- **FEAT**(attachments): add error handlers (#65).
- **DOCS**: update readmes (#38).
- **BREAKING** **FEAT**(attachments): cater for subdirectories in storage (#78).

## 0.4.1

- Reduce version number of `path_provider` to `2.0.13`

## 0.4.0

- BREAKING CHANGE: Generalize naming so `savePhoto` and `deletePhoto` have been removed in favour of `saveFile` and `deleteFile`
- Added optional subDirectories argument when initializing the queue so that local subDirectories are created to match any subDirectories on the storage provider allowing files to be saved instead of an error being thrown.

## 0.3.2

- Fix sync not resetting after an error is thrown

## 0.3.1

- Add periodic syncing and deleting of attachments
- Remove unnecessary delete
- Fix loop

## 0.3.0

- BREAKING CHANGE: `reconcileId` has been removed in favour of `reconcileIds`. This will require a change to `watchIds` implementation which is shown in `example/getting_started.dart`
- Improved queue so that uploads, downloads and deletes do not happen multiple times

## 0.3.0-alpha.1

- Added initial support for Web platforms

## 0.2.1

- Added `onUploadError` as an optional function that can be set when setting up the queue to handle upload errors
- Added `onDownloadError` as an optional function that can be set when setting up the queue to handle upload errors

## 0.2.0

- Potentially BREAKING CHANGE for users who rely on multiple attachment queues.
  Moved away from randomly generating queue table name in favour of a user creating a queue and table using a name of their choosing.

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

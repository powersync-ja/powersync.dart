# powersync_devtools_extension

A [DevTools extension](https://pub.dev/packages/devtools_extensions) for PowerSync.

## Getting Started

To work on the extension, you can launch this project in a simulated environment. On the command line,
launch `flutter run -d chrome --dart-define=use_simulated_environment=true`.
If you want to launch from VS Code, this configuration might be convenient:

```json
    {
        "name": "DevTools extension",
        "type": "dart",
        "request": "launch",
        "program": "lib/main.dart",
        "cwd": "packages/powersync_devtools_extension",
        "args": [
            "--dart-define=use_simulated_environment=true"
        ]
    }
```

Next, start a Dart or Flutter app using a PowerSync database.
When using `dart run`, include the `--observe` flag to start the VM service. For Flutter apps,
the service is started by default.

As the app starts, look for a message similar to the following:

```
A Dart VM Service on macOS is available at: http://127.0.0.1:64161/nGx5zVEtGlk=/
```

Copy that URL and paste it into the extension to inspect databases.

## Building

To make it available for users, the DevTools extension is copied into the `powersync` package.
The `tool/build.sh` command is responsible for that. After running it, you can open any demo
using PowerSync, open DevTools and navigate to the PowerSync screen to use the extension.
In VS Code, the "Dart: Open DevTools in Browser" command is convenient for this.

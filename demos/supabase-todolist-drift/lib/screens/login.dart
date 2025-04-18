import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../components/app_bar.dart';
import '../navigation.dart';
import '../supabase.dart';

@RoutePage()
final class LoginPage extends HookConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usernameController = useTextEditingController();
    final passwordController = useTextEditingController();
    final (:error, :isBusy) = ref.watch(authNotifierProvider);

    final loginAction = isBusy
        ? null
        : () {
            ref
                .read(authNotifierProvider.notifier)
                .login(usernameController.text, passwordController.text);
          };

    return Scaffold(
      appBar: appBar,
      body: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.all(30),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 15),
                  child: Text('Supabase Signup'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: "Email"),
                    enabled: !isBusy,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: TextFormField(
                    obscureText: true,
                    controller: passwordController,
                    decoration: InputDecoration(
                        labelText: "Password", errorText: error),
                    enabled: !isBusy,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: TextButton(
                    onPressed: loginAction,
                    child: const Text('Login'),
                  ),
                ),
                TextButton(
                  onPressed: isBusy
                      ? null
                      : () {
                          ref.read(appRouter).replace(const SignupRoute());
                        },
                  child: const Text('Sign Up'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

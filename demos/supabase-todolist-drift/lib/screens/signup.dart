import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../components/app_bar.dart';
import '../navigation.dart';
import '../supabase.dart';

@RoutePage()
final class SignupPage extends HookConsumerWidget {
  const SignupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usernameController = useTextEditingController();
    final passwordController = useTextEditingController();
    final (:error, :isBusy) = ref.watch(authNotifierProvider);

    final signupAction = isBusy
        ? null
        : () {
            ref
                .read(authNotifierProvider.notifier)
                .signup(usernameController.text, passwordController.text);
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
                  child: Text('Supabase Login'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    enabled: !isBusy,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: TextFormField(
                    obscureText: true,
                    controller: passwordController,
                    decoration: InputDecoration(
                        labelText: 'Password', errorText: error),
                    enabled: !isBusy,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: TextButton(
                    onPressed: signupAction,
                    child: const Text('Sign up'),
                  ),
                ),
                TextButton(
                  onPressed: isBusy
                      ? null
                      : () {
                          ref.read(appRouter).replace(const LoginRoute());
                        },
                  child: const Text('Already have an account?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

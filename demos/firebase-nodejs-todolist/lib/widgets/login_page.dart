import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late TextEditingController _passwordController;
  late TextEditingController _usernameController;
  String? _error;
  late bool _busy;

  @override
  void initState() {
    super.initState();

    _busy = false;
    _passwordController = TextEditingController(text: '');
    _usernameController = TextEditingController(text: '');
  }

  void _login(BuildContext context) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _usernameController.text, password: _passwordController.text);
      if (context.mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (context) => listsPage,
        ));
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        setState(() {
          _error = 'No user found for that email.';
        });
      } else if (e.code == 'wrong-password') {
        setState(() {
          _error = 'Wrong password provided for that user.';
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("PowerSync Flutter Demo"),
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Center(
                child: SizedBox(
                  width: 300,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Firebase Email Login'),
                      const SizedBox(height: 35),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(labelText: "Email"),
                        enabled: !_busy,
                        onFieldSubmitted: _busy
                            ? null
                            : (String value) {
                                _login(context);
                              },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        obscureText: true,
                        controller: _passwordController,
                        decoration: InputDecoration(
                            labelText: "Password", errorText: _error),
                        enabled: !_busy,
                        onFieldSubmitted: _busy
                            ? null
                            : (String value) {
                                _login(context);
                              },
                      ),
                      const SizedBox(height: 25),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                _login(context);
                              },
                        child: const Text('Login'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => signupPage,
                                ));
                              },
                        child: const Text('Sign Up'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:powersync_django_todolist_demo/api_client.dart';
import 'package:powersync_django_todolist_demo/app_config.dart';
import 'package:powersync_django_todolist_demo/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final ApiClient apiClient = ApiClient(AppConfig.djangoUrl);

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await apiClient.authenticate(
          _usernameController.text, _passwordController.text);

      final payload = _parseJwt(session['access_token']);
      if (payload.containsKey('sub')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('id', payload['sub'].toString());

        //re-init PowerSync manually for first time sign in
        await openDatabase();
      } else {
        setState(() {
          _error = 'Invalid token payload';
        });
      }

      if (context.mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (context) => listsPage,
        ));
      }
    } on Exception catch (e) {
      setState(() {
        _error = e.toString();
      });
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

  Map<String, dynamic> _parseJwt(String token) {
    final parts = token.split('.');
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return json.decode(decoded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("PowerSync Django Todolist Demo"),
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
                      const Text('Login'),
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
  }
}

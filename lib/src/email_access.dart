import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum EmailAccessMode { signIn, register }

class EmailAccess extends StatefulWidget {
  const EmailAccess({super.key});
  @override
  State<EmailAccess> createState() => _EmailAccessState();
}

class _EmailAccessState extends State<EmailAccess> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _name = TextEditingController();
  EmailAccessMode _mode = EmailAccessMode.signIn;
  bool _busy = false;
  String? _message;
  bool _success = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _name.dispose();
    super.dispose();
  }

  static String errorMessage(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' => 'The email or password is incorrect.',
        'email-already-in-use' || 'credential-already-in-use' => 'This email already has an account. Sign in to that account or use password reset.',
        'weak-password' || 'password-does-not-meet-requirements' =>
          'Choose a stronger password that meets the account requirements.',
        'too-many-requests' => 'Too many attempts. Please wait and try again.',
        'network-request-failed' => 'Check your connection and try again.',
        'operation-not-allowed' => 'Email sign-in has not been enabled yet.',
        'requires-recent-login' =>
          'Please sign out and sign in again, then retry this change.',
        'user-disabled' => 'This account cannot access the app.',
        _ => 'The request could not be completed. Please try again.',
      };
    }
    return 'The request could not be completed. Please try again.';
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
      _success = false;
    });
    try {
      final auth = FirebaseAuth.instance;
      final email = _email.text.trim();
      if (_mode == EmailAccessMode.signIn) {
        await auth.signInWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
      } else if (_mode == EmailAccessMode.register) {
        final result = await auth.createUserWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
        await result.user!.updateDisplayName(_name.text.trim());
        await result.user!.getIdToken(true);
      }
      if (mounted) {
        _password.clear();
        _confirmation.clear();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = errorMessage(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _message = 'Enter your email address first.';
        _success = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() {
          _success = true;
          _message = 'If this email has an account, a password reset email is on its way.';
        });
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _success = error.code == 'user-not-found';
          _message = _success
              ? 'If this email has an account, a password reset email is on its way.'
              : errorMessage(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final registration = _mode == EmailAccessMode.register;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (registration)
            TextFormField(
              controller: _name,
              enabled: !_busy,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Your name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your name.'
                  : null,
            ),
          TextFormField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (value) =>
                value == null ||
                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(value.trim())
                ? 'Enter a valid email address.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: [
              registration ? AutofillHints.newPassword : AutofillHints.password,
            ],
            decoration: InputDecoration(labelText: 'Password'),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Enter your password.';
              if ((registration) && value.length < 8) {
                return 'Use at least 8 characters.';
              }
              return null;
            },
            onFieldSubmitted: (_) {
              if (!registration && !_busy) _submit();
            },
          ),
          if (registration) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmation,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (value) =>
                  value != _password.text ? 'Passwords do not match.' : null,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy
                  ? 'Please wait…'
                  : registration
                  ? 'Create account'
                  : 'Sign in with email',
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _form.currentState?.reset();
                        _mode = registration
                            ? EmailAccessMode.signIn
                            : EmailAccessMode.register;
                        _message = null;
                        _password.clear();
                        _confirmation.clear();
                      }),
                child: Text(
                  registration
                      ? 'Already have an account? Sign in'
                      : 'Create an account',
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _reset,
                child: const Text('Forgot password?'),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: TextStyle(
                color: _success
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

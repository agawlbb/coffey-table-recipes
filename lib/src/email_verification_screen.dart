import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'invitation_entry.dart';

/// Keeps unverified accounts out of household setup while verification is pending.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.user,
    required this.refresh,
    required this.signOut,
  });
  final User user;
  final Future<void> Function() refresh;
  final Future<void> Function() signOut;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _sending = false;
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _send();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_checking) return;
    _checking = true;
    try {
      await widget.refresh();
    } catch (_) {
      // A transient connection failure should not interrupt the instructions.
    } finally {
      _checking = false;
    }
  }

  Future<void> _send({bool resend = false}) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await InvitationVerification.send(widget.user, resend: resend);
      if (mounted) {
        setState(
          () => _message =
              'Verification email sent. Check your inbox and spam folder.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'The verification email could not be sent. Please try resending it.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Coffey Table'),
      actions: [
        TextButton(onPressed: widget.signOut, child: const Text('Sign out')),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    'Verify your email',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Open the verification email sent to ${widget.user.email ?? 'your email address'} and click its link to complete verification.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Return here after verifying. This screen will continue automatically once your email is verified.',
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(_message!),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _sending ? null : () => _send(resend: true),
                    child: Text(
                      _sending ? 'Sending…' : 'Resend verification email',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'invitation_entry.dart';
import 'api.dart';

/// Keeps unverified accounts out of household setup while verification is pending.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.user,
    required this.refresh,
    required this.signOut,
    this.registerAccount,
  });
  final User user;
  final Future<void> Function() refresh;
  final Future<void> Function() signOut;
  final Future<void> Function()? registerAccount;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _cooldownTimer;
  int get _remainingSeconds =>
      (InvitationVerification.resendRemaining(widget.user.uid).inMilliseconds /
              1000)
          .ceil();
  bool _sending = false;
  bool _checking = false;
  String? _message;
  Future<void>? _observedAttempt;
  String? _registrationError;
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _refresh();
    InvitationVerification.changes.addListener(_signupAttemptChanged);
    _signupAttemptChanged();
    _registerAccount();
  }

  Future<void> _registerAccount() async {
    if (_registering || widget.registerAccount == null) return;
    setState(() {
      _registering = true;
      _registrationError = null;
    });
    try {
      await widget.registerAccount!();
    } catch (_) {
      if (mounted) {
        setState(
          () => _registrationError = 'Your login account was created, but could not be registered with the recipe service. Retry to finish account setup.',
        );
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  void _signupAttemptChanged() {
    _updateCooldown();
    final attempt = InvitationVerification.attemptFor(widget.user.uid);
    if (attempt != null && attempt != _observedAttempt && mounted) {
      _observedAttempt = attempt;
      _observe(attempt);
    }
  }

  void _updateCooldown() {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() {});
    if (_remainingSeconds > 0) {
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _remainingSeconds == 0) timer.cancel();
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cooldownTimer?.cancel();
    InvitationVerification.changes.removeListener(_signupAttemptChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _updateCooldown();
    }
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
    if (_sending || _remainingSeconds > 0) return;
    await InvitationVerification.send(
      widget.user,
      resend: resend,
    ).catchError((Object _) {});
  }

  Future<void> _observe(Future<void> attempt) async {
    if (!mounted) return;
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await attempt;
      if (mounted) {
        setState(
          () => _message =
              'Verification email sent. Check your inbox and spam folder.',
        );
      }
    } catch (error) {
      if (mounted) {
        final connectionInterrupted =
            error is TimeoutException ||
            (error is ApiException && error.code == 'connection_lost');
        final message = connectionInterrupted
            ? 'The connection was interrupted before verification email delivery was confirmed. Check your inbox before resending.'
            : error is FirebaseAuthException
            ? switch (error.code) {
                'too-many-requests' => 'Firebase rejected the verification email request (too-many-requests). No email was sent. Firebase does not provide a retry time.',
                'network-request-failed' => 'The verification email could not be sent. Check your connection and resend.',
                _ =>
                  'The verification email could not be sent (${error.code}). Please try resending it.',
              }
            : error is ApiException
            ? error.message
            : 'The verification email could not be sent. Please try resending it.';
        setState(() => _message = message);
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
                    'Verify ${widget.user.email ?? 'your email address'} using the link in your verification email. Check your inbox and spam folder after sending is confirmed.',
                  ),
                  const SizedBox(height: 12),
                  if (_registrationError != null) ...[
                    const SizedBox(height: 16),
                    Text(_registrationError!),
                    TextButton(
                      onPressed: _registering ? null : _registerAccount,
                      child: const Text('Retry account setup'),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(_message!),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _sending || _remainingSeconds > 0
                        ? null
                        : () => _send(resend: true),
                    child: Text(
                      _sending
                          ? 'Sending…'
                          : _remainingSeconds > 0
                          ? 'Resend in ${_remainingSeconds}s'
                          : 'Resend verification email',
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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'invitation_entry.dart';

String _errorMessage(Object error) => error is ApiException
    ? error.message
    : 'The request could not be completed. Please try again.';

class InvitePersonDialog extends StatefulWidget {
  const InvitePersonDialog({
    super.key,
    required this.personName,
    required this.send,
  });
  final String personName;
  final Future<void> Function(String email) send;
  @override
  State<InvitePersonDialog> createState() => _InvitePersonDialogState();
}

class _InvitePersonDialogState extends State<InvitePersonDialog> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.send(_email.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _errorMessage(error);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Invite ${widget.personName}'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _email,
              autofocus: true,
              enabled: !_busy,
              maxLength: 254,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Invitee email'),
              validator: (value) =>
                  value == null ||
                      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(value.trim())
                  ? 'Enter a valid email address.'
                  : null,
              onFieldSubmitted: (_) => _send(),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Sending…' : 'Send invitation'),
        ),
      ],
    ),
  );
}

class InvitationResponseDialog extends StatefulWidget {
  const InvitationResponseDialog({
    super.key,
    required this.invitation,
    required this.respond,
  });
  final Map<String, dynamic> invitation;
  final Future<void> Function(String decision) respond;
  @override
  State<InvitationResponseDialog> createState() =>
      _InvitationResponseDialogState();
}

class _InvitationResponseDialogState extends State<InvitationResponseDialog> {
  bool _busy = false;
  String? _error;
  Future<void> _respond(String decision) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.respond(decision);
      if (mounted) Navigator.pop(context, decision == 'accept');
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('Household invitation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.invitation['inviter_name'] ?? 'A household administrator'} has invited you to join ${widget.invitation['household_name']}.',
          ),
          const SizedBox(height: 12),
          const Text('Accept to share this household’s recipes.'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        TextButton(
          onPressed: _busy ? null : () => _respond('decline'),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _respond('accept'),
          child: const Text('Accept'),
        ),
      ],
    ),
  );
}

class InvitationVerificationDialog extends StatefulWidget {
  const InvitationVerificationDialog({super.key, required this.user});
  final User user;
  @override
  State<InvitationVerificationDialog> createState() =>
      _InvitationVerificationDialogState();
}

class _InvitationVerificationDialogState
    extends State<InvitationVerificationDialog> {
  bool _busy = false;
  String? _message;
  Future<void> _verify({required bool check}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (check) {
        await widget.user.reload();
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.emailVerified) {
          await user.getIdToken(true);
          if (mounted) Navigator.pop(context, true);
          return;
        }
        if (mounted) {
          setState(
            () => _message = 'Your email is not verified yet. Open the verification link, then check again.',
          );
        }
      } else {
        await InvitationVerification.send(widget.user, resend: true);
        if (mounted) {
          setState(
            () => _message =
                'Verification email sent. Open its link, then return here.',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'Could not verify your email. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('You have a household invitation'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Verify your email address to review and accept or decline your invitation.',
        ),
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!)],
        if (_busy) const LinearProgressIndicator(),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Later'),
      ),
      TextButton(
        onPressed: _busy ? null : () => _verify(check: false),
        child: const Text('Resend verification email'),
      ),
      FilledButton(
        onPressed: _busy ? null : () => _verify(check: true),
        child: const Text('I verified my email'),
      ),
    ],
  );
}

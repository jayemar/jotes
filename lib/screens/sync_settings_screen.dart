import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AutofillHints, TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  final _urlCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _register = false;
  bool _obscurePassword = true;
  bool _resyncing = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _urlCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (url.isEmpty || email.isEmpty || password.isEmpty) return;

    await ref
        .read(syncProvider.notifier)
        .connect(
          url: url,
          email: email,
          password: password,
          register: _register,
        );
    // Tells the platform autofill service (password managers included)
    // that this form's submission is done, so it can offer to save a
    // newly entered credential - without this, a password manager may
    // only ever offer to *fill* an already-saved entry, never prompt to
    // save a new one after a successful sign-in/registration.
    TextInput.finishAutofillContext();
  }

  /// Forces a full reconciliation right now (see SyncNotifier.resync) -
  /// mainly useful when another device's change (a delete especially)
  /// hasn't shown up here yet, e.g. because this device has no working
  /// background push and simply hasn't reconnected since.
  Future<void> _resync() async {
    setState(() => _resyncing = true);
    try {
      await ref.read(syncProvider.notifier).resync();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Synced')));
    } finally {
      if (mounted) setState(() => _resyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (syncState.status) {
          SyncStatus.connected => _buildConnected(syncState),
          SyncStatus.connecting => const Center(
            child: CircularProgressIndicator(),
          ),
          SyncStatus.disconnected || SyncStatus.error => _buildForm(syncState),
        },
      ),
    );
  }

  Widget _buildConnected(SyncState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.cloud_done, size: 48, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          'Connected to:',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text('${state.serverUrl}'),
        const SizedBox(height: 12),
        Text('Signed in as ${state.userEmail}'),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                key: const Key('sync_now_button'),
                onPressed: _resyncing ? null : _resync,
                child: _resyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sync now'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                key: const Key('sync_disconnect_button'),
                onPressed: () => ref.read(syncProvider.notifier).disconnect(),
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildForm(SyncState state) {
    return ListView(
      children: [
        const Text(
          'Sync your notes across devices with a self-hosted PocketBase '
          'server (see backend/ in the project for the Dockerfile).',
        ),
        const SizedBox(height: 16),
        if (state.status == SyncStatus.error)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Could not connect: ${state.errorMessage}',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        TextField(
          key: const Key('sync_url_field'),
          controller: _urlCtrl,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'http://your-server:8090',
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        // Email/password grouped so the platform autofill service (and
        // password managers hooking into it) treats them as one form -
        // without an AutofillGroup and per-field autofillHints, neither
        // field is identifiable as a credential at all, which is why a
        // password manager wouldn't offer to fill or save either one.
        AutofillGroup(
          child: Column(
            children: [
              TextField(
                key: const Key('sync_email_field'),
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.username,
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('sync_password_field'),
                controller: _passwordCtrl,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    key: const Key('sync_password_visibility_toggle'),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
              ),
            ],
          ),
        ),
        SwitchListTile(
          key: const Key('sync_register_switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Create a new account'),
          subtitle: const Text('Off = log into an existing account'),
          value: _register,
          onChanged: (v) => setState(() => _register = v),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('sync_submit_button'),
          onPressed: _submit,
          child: Text(_register ? 'Create account & connect' : 'Connect'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() =>
      _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  final _urlCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _register = false;

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

    await ref.read(syncProvider.notifier).connect(
          url: url,
          email: email,
          password: password,
          register: _register,
        );
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
          SyncStatus.connecting =>
            const Center(child: CircularProgressIndicator()),
          SyncStatus.disconnected ||
          SyncStatus.error =>
            _buildForm(syncState),
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
        Text(
          'Connected to ${state.serverUrl}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text('Signed in as ${state.userEmail}'),
        const SizedBox(height: 24),
        FilledButton.tonal(
          key: const Key('sync_disconnect_button'),
          onPressed: () => ref.read(syncProvider.notifier).disconnect(),
          child: const Text('Disconnect'),
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
            hintText: 'https://your-server:8090',
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('sync_email_field'),
          controller: _emailCtrl,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('sync_password_field'),
          controller: _passwordCtrl,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
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

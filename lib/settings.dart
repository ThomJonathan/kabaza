import 'package:flutter/material.dart';
import 'package:kabanza/deleteAccount.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDeleting = false;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    final data = await Supabase.instance.client
        .from('users')
        .select('full_name, role')
        .eq('id', user.id)
        .maybeSingle();
    setState(() {
      _userData = data;
      _isLoading = false;
    });
  }

  Future<void> _handleChangePassword() async {
    Navigator.pushNamed(context, '/change-password');
  }

  Future<void> _handleDeleteAccount() async {
    setState(() => _isDeleting = true);
    final deletionService = UserDeletionService(Supabase.instance.client);
    final success = await deletionService.deleteMyAccount(context);
    setState(() => _isDeleting = false);

    if (success && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_userData != null) ...[
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        child: Text(
                          (_userData!['full_name']?.isNotEmpty == true)
                              ? _userData!['full_name'][0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userData!['full_name'] ?? 'Unknown',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Role: ${_userData!['role'] ?? 'Unknown'}',
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change Password'),
                  onTap: _handleChangePassword,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
                  onTap: _isDeleting ? null : _handleDeleteAccount,
                  trailing: _isDeleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ],
            ),
    );
  }
}

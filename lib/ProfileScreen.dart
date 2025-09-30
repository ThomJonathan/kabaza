import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  String? _userId;
  String? _fullName;
  String? _email;
  String? _phone;
  String? _role;
  String? _profileUrl;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    final user = supabase.auth.currentUser;
    if (user == null || user.id == null) return; // Add null check for user.id
    final response = await supabase
        .from('users')
        .select()
        .eq('id', user.id!) // Use non-nullable value
        .single();
    setState(() {
      _userId = response['id'];
      _fullName = response['full_name'];
      _email = response['email'];
      _phone = response['phone'];
      _role = response['role'];
      _profileUrl = response['profile_url'];
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await supabase.from('users').update({
        'full_name': _fullName,
        'phone': _phone,
        'profile_url': _profileUrl,
      }).eq('id', _userId ?? ''); // Ensure Object type, fallback to empty string if null
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Profile picture (optional)
              if (_profileUrl != null && _profileUrl!.isNotEmpty)
                CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage(_profileUrl!),
                )
              else
                CircleAvatar(
                  radius: 40,
                  child: Text(
                    (_fullName?.isNotEmpty ?? false) ? _fullName![0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              const SizedBox(height: 24),
              TextFormField(
                initialValue: _fullName,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => _fullName = val,
                validator: (val) => val == null || val.isEmpty ? 'Enter your name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _email,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
                enabled: false,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => _phone = val,
                validator: (val) => val == null || val.isEmpty ? 'Enter your phone number' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
                enabled: false,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

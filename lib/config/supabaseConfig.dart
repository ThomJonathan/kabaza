
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

class SupabaseConfig {
  static const String supabaseUrl = 'https://xagaehyzcnobvvmaykvt.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhhZ2FlaHl6Y25vYnZ2bWF5a3Z0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgzMzM4MTIsImV4cCI6MjA2MzkwOTgxMn0.Mu-hA4ZoybE_vddgCLqo-gaZmI4vNLB2SWKGLTGMlBk';

  static Future<void> initialize() async {
    try {
      print('🚀 Starting Supabase initialization...');
      print('📍 URL: $supabaseUrl');
      print('🔑 Key length: ${supabaseAnonKey.length} characters');

      // First test basic network connectivity
      await testNetworkConnectivity();

      // Then initialize Supabase
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        debug: true,
      );

      print('✅ Supabase initialized successfully');

      // Test the connection
      await testSupabaseConnection();

    } catch (e, stackTrace) {
      print('❌ Supabase initialization error: $e');
      print('📚 Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<void> testNetworkConnectivity() async {
    print('\n🌐 Testing network connectivity...');

    try {
      // For web, we can't use InternetAddress.lookup
      // Instead, we'll test with a simple HTTP request
      print('🔍 Testing HTTP connectivity (web version)...');

      // Test basic HTTP request using Supabase client
      final client = Supabase.instance.client;

      // Try a simple request that should work
      await client.auth.getUser();
      print('✅ HTTP connectivity test passed!');

      print('✅ All network tests passed!\n');

    } catch (e, stackTrace) {
      print('❌ Network test failed: $e');
      print('📚 Network stack trace: $stackTrace');
      print('💡 This suggests a network connectivity issue\n');
      // Don't rethrow here since this is just a test
    }
  }

  static Future<void> testSupabaseConnection() async {
    print('🔌 Testing Supabase connection...');

    try {
      // Test 1: Client access
      final client = Supabase.instance.client;
      print('✅ Client access successful');

      // Test 2: Check auth state
      final user = client.auth.currentUser;
      print('👤 Current user: ${user?.id ?? 'No user logged in'}');

      // Test 3: Simple auth test (this should work without any tables)
      print('🔍 Testing auth connection...');

      try {
        // Try to sign in with invalid credentials - this will test the connection
        // without actually signing in (expected to fail with auth error, not connection error)
        await client.auth.signInWithPassword(
          email: 'test@test.com',
          password: 'invalid',
        );
      } catch (authError) {
        if (authError.toString().contains('Invalid login credentials')) {
          print('✅ Auth connection test successful (got expected auth error)');
        } else {
          print('⚠️ Auth test got unexpected error: $authError');
        }
      }

      print('✅ Supabase connection is working!');

    } catch (e, stackTrace) {
      print('❌ Supabase connection test failed: $e');
      print('📚 Supabase stack trace: $stackTrace');

      // Additional error analysis
      if (e.toString().contains('Operation not permitted')) {
        print('💡 This is likely a macOS sandbox/permission issue');
        print('💡 Check your entitlements files for network permissions');
      } else if (e.toString().contains('Connection refused')) {
        print('💡 This suggests a firewall or network blocking issue');
      } else if (e.toString().contains('timeout')) {
        print('💡 This suggests a slow network or blocked connection');
      }

      rethrow;
    }
  }

  // Alternative minimal test that should work
  static Future<void> testMinimal() async {
    print('\n🧪 Running minimal test...');

    try {
      // Just try to create a client instance without making any network calls
      final client = Supabase.instance.client;
      print('✅ Client instance created');

      // Check if we can access basic properties
      print('🔍 Auth client type: ${client.auth.runtimeType}');
      print('✅ Minimal test passed');

    } catch (e) {
      print('❌ Even minimal test failed: $e');
    }
  }
}

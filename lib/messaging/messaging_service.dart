import 'package:supabase_flutter/supabase_flutter.dart';

class MessagingService {
  final SupabaseClient supabase;
  MessagingService(this.supabase);

  String? get currentUserId => supabase.auth.currentUser?.id;

  Future<String> generateConversationId(String user1Id, String user2Id) async {
    try {
      // Try using the RPC function first
      final res = await supabase.rpc('generate_conversation_id', params: {
        'user1_id': user1Id,
        'user2_id': user2Id,
      });
      if (res != null) {
        return res as String;
      }
    } catch (e) {
      print('RPC failed, using fallback: $e');
    }

    // Fallback: create a deterministic conversation ID by sorting the user IDs
    final sortedIds = [user1Id, user2Id]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  Future<List<Map<String, dynamic>>> fetchConversationList() async {
    final me = currentUserId;
    if (me == null) return [];

    try {
      // Get conversations from messages table directly
      return await _getConversationsFromMessages();
    } catch (e) {
      print('Error fetching conversation list: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getConversationsFromMessages() async {
    final me = currentUserId;
    if (me == null) return [];

    try {
      // Get latest message from each conversation with user names
      final rows = await supabase
          .from('messages')
          .select('''
            *,
            sender:users!messages_sender_id_fkey(id, full_name, profile_url),
            receiver:users!messages_receiver_id_fkey(id, full_name, profile_url)
          ''')
          .or('sender_id.eq.$me,receiver_id.eq.$me')
          .order('created_at', ascending: false);

      print('Fetched ${rows.length} messages for conversation list');

      // Group by conversation and get the latest message
      final Map<String, Map<String, dynamic>> conversations = {};

      for (final row in rows) {
        final convId = row['conversation_id'] as String?;
        if (convId == null) continue;

        if (!conversations.containsKey(convId)) {
          final isFromMe = row['sender_id'] == me;
          final otherUserId = isFromMe ? row['receiver_id'] : row['sender_id'];

          // Get the other user's info
          final senderInfo = row['sender'] as Map<String, dynamic>?;
          final receiverInfo = row['receiver'] as Map<String, dynamic>?;

          String otherUserName = 'User'; // Default fallback
          String? otherUserAvatar;

          if (isFromMe && receiverInfo != null) {
            otherUserName = receiverInfo['full_name'] ?? 'User';
            otherUserAvatar = receiverInfo['profile_url'];
          } else if (!isFromMe && senderInfo != null) {
            otherUserName = senderInfo['full_name'] ?? 'User';
            otherUserAvatar = senderInfo['profile_url'];
          }

          conversations[convId] = {
            'conversation_id': convId,
            'other_user_id': otherUserId,
            'other_user_name': otherUserName,
            'other_user_avatar': otherUserAvatar,
            'last_message': row['message_text'] ?? '',
            'last_message_time': row['created_at'],
            'unread_count': 0, // Will be calculated below
          };

          print('Added conversation: $convId with ${otherUserName}');
        }
      }

      // Calculate unread counts
      for (final convId in conversations.keys) {
        try {
          final unreadResponse = await supabase
              .from('messages')
              .select('id')
              .eq('conversation_id', convId)
              .eq('receiver_id', me)
              .eq('is_read', false);
          conversations[convId]!['unread_count'] = (unreadResponse as List).length;
        } catch (e) {
          print('Error counting unread messages for $convId: $e');
          conversations[convId]!['unread_count'] = 0;
        }
      }

      final result = conversations.values.toList();
      result.sort((a, b) {
        final aTime = a['last_message_time'] as String?;
        final bTime = b['last_message_time'] as String?;
        if (aTime == null || bTime == null) return 0;
        return DateTime.parse(bTime).compareTo(DateTime.parse(aTime));
      });

      print('Returning ${result.length} conversations');
      return result;
    } catch (e) {
      print('Error getting conversations from messages: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchConversationMessagesByOtherUser(String otherUserId) async {
    final me = currentUserId;
    if (me == null) throw Exception('Not authenticated');
    final convId = await generateConversationId(me, otherUserId);
    return fetchConversationMessages(convId);
  }

  Future<List<Map<String, dynamic>>> fetchConversationMessages(String conversationId) async {
    try {
      // Fetch from messages table directly without views or profile joins
      // Order by created_at ASC to get oldest messages first
      final rows = await supabase
          .from('messages')
          .select('*')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true); // Ensure oldest first

      print('Fetched messages from database: ${rows.length} messages');
      for (final row in rows) {
        print('Message: ${row['message_text']} at ${row['created_at']}');
      }

      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error fetching messages: $e');
      throw e;
    }
  }

  Future<void> markConversationRead(String conversationId) async {
    final me = currentUserId;
    if (me == null) return;

    try {
      await supabase.from('messages').update({'is_read': true}).match({
        'conversation_id': conversationId,
        'receiver_id': me,
        'is_read': false,
      });
    } catch (e) {
      print('Error marking conversation as read: $e');
    }
  }

  Future<Map<String, dynamic>> sendTextMessage({
    required String toUserId,
    String? rideRequestId,
    required String text
  }) async {
    final me = currentUserId;
    if (me == null) throw Exception('Not authenticated');

    final convId = await generateConversationId(me, toUserId);

    print('Sending message to conversation: $convId');
    print('From: $me, To: $toUserId');
    print('Message: $text');

    try {
      final result = await supabase.from('messages').insert({
        'conversation_id': convId,
        'sender_id': me,
        'receiver_id': toUserId,
        'ride_request_id': rideRequestId,
        'message_text': text,
        'message_type': 'text',
        'is_read': false,
        'is_delivered': true, // Mark as delivered immediately since we're using Supabase
      }).select().single(); // Get the inserted message back

      print('Message sent successfully: $result');
      return result as Map<String, dynamic>;
    } catch (e) {
      print('Error sending message: $e');
      throw e;
    }
  }

  Future<void> deleteConversationWithUser(String otherUserId) async {
    final me = currentUserId;
    if (me == null) throw Exception('Not authenticated');
    final convId = await generateConversationId(me, otherUserId);
    await deleteConversation(convId);
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      await supabase.from('messages').delete().eq('conversation_id', conversationId);
    } catch (e) {
      print('Error deleting conversation: $e');
      throw e;
    }
  }

  /// Creates a more reliable real-time subscription with enhanced error handling
  RealtimeChannel subscribeToConversation(
      String conversationId,
      void Function(Map<String, dynamic> payload) onChange
      ) {
    // Generate a unique channel name to avoid conflicts
    final channelName = 'messages_${conversationId}_${DateTime.now().millisecondsSinceEpoch}';
    final channel = supabase.channel(channelName);

    print('Creating realtime subscription for conversation: $conversationId');
    print('Channel name: $channelName');

    // Subscribe to INSERT events (new messages) - explicitly use public schema
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public', // Explicitly specify public schema
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'conversation_id',
        value: conversationId,
      ),
      callback: (payload) {
        print('Realtime INSERT received: ${payload.newRecord}');
        final newMessage = payload.newRecord;
        if (newMessage != null) {
          // Ensure conversation_id is included
          newMessage['conversation_id'] = conversationId;
          onChange(newMessage);
        }
      },
    );

    // Subscribe to UPDATE events (message status changes like read/delivered)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public', // Explicitly specify public schema
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'conversation_id',
        value: conversationId,
      ),
      callback: (payload) {
        print('Realtime UPDATE received: ${payload.newRecord}');
        final updatedMessage = payload.newRecord;
        if (updatedMessage != null) {
          updatedMessage['conversation_id'] = conversationId;
          onChange(updatedMessage);
        }
      },
    );

    // Enhanced subscription with better error handling
    channel.subscribe((status, [error]) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          print('✅ Successfully subscribed to realtime updates for $conversationId');
          break;
        case RealtimeSubscribeStatus.timedOut:
          print('⏰ Realtime subscription timed out for $conversationId');
          // Auto-retry after timeout
          Future.delayed(const Duration(seconds: 3), () {
            print('🔄 Retrying subscription...');
            channel.subscribe();
          });
          break;
        case RealtimeSubscribeStatus.closed:
          print('🔒 Realtime subscription closed for $conversationId');
          break;
        case RealtimeSubscribeStatus.channelError:
          print('❌ Realtime channel error for $conversationId: $error');
          break;
      }
    });

    return channel;
  }

  /// Utility method to check Supabase connection status
  Future<bool> checkConnection() async {
    try {
      await supabase.from('messages').select('id').limit(1);
      return true;
    } catch (e) {
      print('Connection check failed: $e');
      return false;
    }
  }

  /// Force refresh a conversation's messages
  Future<List<Map<String, dynamic>>> refreshConversation(String conversationId) async {
    print('🔄 Refreshing conversation: $conversationId');
    return await fetchConversationMessages(conversationId);
  }
}
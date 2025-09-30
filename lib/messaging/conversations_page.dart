import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'messaging_service.dart';
import 'chat_page.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  final _client = Supabase.instance.client;
  late final MessagingService _svc;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _svc = MessagingService(_client);
    _load();
    _subscribeToAllMessages();
  }

  @override
  void dispose() {
    if (_messagesChannel != null) {
      _client.removeChannel(_messagesChannel!);
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _svc.fetchConversationList();
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (e) {
      print('Error loading conversations: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _subscribeToAllMessages() {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return;

    // Remove existing channel first
    if (_messagesChannel != null) {
      _client.removeChannel(_messagesChannel!);
    }

    // Create a unique channel name for this user's message updates
    final channelName = 'all_messages_${currentUserId}_${DateTime.now().millisecondsSinceEpoch}';
    _messagesChannel = _client.channel(channelName);

    print('Subscribing to all messages for user: $currentUserId');

    // Subscribe to new message INSERTs where current user is sender or receiver
    _messagesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        print('New message detected: ${payload.newRecord}');
        final newMessage = payload.newRecord;
        if (newMessage != null && mounted) {
          final senderId = newMessage['sender_id'] as String?;
          final receiverId = newMessage['receiver_id'] as String?;

          // Only process if current user is involved in this message
          if (senderId == currentUserId || receiverId == currentUserId) {
            print('Message involves current user, refreshing conversations...');
            _handleNewMessage(newMessage);
          }
        }
      },
    );

    // Subscribe to message UPDATEs (like read status changes)
    _messagesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        print('Message updated: ${payload.newRecord}');
        final updatedMessage = payload.newRecord;
        if (updatedMessage != null && mounted) {
          final senderId = updatedMessage['sender_id'] as String?;
          final receiverId = updatedMessage['receiver_id'] as String?;

          // Only process if current user is involved in this message
          if (senderId == currentUserId || receiverId == currentUserId) {
            print('Message update involves current user, refreshing conversations...');
            _handleMessageUpdate(updatedMessage);
          }
        }
      },
    );

    _messagesChannel!.subscribe((status, [error]) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          print('✅ Successfully subscribed to all message updates');
          break;
        case RealtimeSubscribeStatus.timedOut:
          print('⏰ All messages subscription timed out, retrying...');
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) _subscribeToAllMessages();
          });
          break;
        case RealtimeSubscribeStatus.closed:
          print('🔒 All messages subscription closed');
          break;
        case RealtimeSubscribeStatus.channelError:
          print('❌ All messages channel error: $error');
          break;
      }
    });
  }

  void _handleNewMessage(Map<String, dynamic> newMessage) {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return;

    final senderId = newMessage['sender_id'] as String?;
    final receiverId = newMessage['receiver_id'] as String?;
    final conversationId = newMessage['conversation_id'] as String?;
    final messageText = newMessage['message_text'] as String?;
    final createdAt = newMessage['created_at'] as String?;

    if (conversationId == null) return;

    // Check if this conversation already exists in our list
    final existingIndex = _items.indexWhere(
            (item) => item['conversation_id'] == conversationId
    );

    if (existingIndex != -1) {
      // Update existing conversation
      setState(() {
        _items[existingIndex]['last_message'] = messageText ?? '';
        _items[existingIndex]['last_message_time'] = createdAt;

        // Update unread count if message is not from current user
        if (senderId != currentUserId) {
          final currentUnread = _items[existingIndex]['unread_count'] as int? ?? 0;
          _items[existingIndex]['unread_count'] = currentUnread + 1;
        }

        // Move this conversation to top by re-sorting
        _items.sort((a, b) {
          final aTime = a['last_message_time'] as String?;
          final bTime = b['last_message_time'] as String?;
          if (aTime == null || bTime == null) return 0;
          return DateTime.parse(bTime).compareTo(DateTime.parse(aTime));
        });
      });
    } else {
      // This might be a new conversation, refresh the entire list
      print('New conversation detected, full refresh...');
      _load();
    }
  }

  void _handleMessageUpdate(Map<String, dynamic> updatedMessage) {
    final conversationId = updatedMessage['conversation_id'] as String?;
    if (conversationId == null) return;

    final existingIndex = _items.indexWhere(
            (item) => item['conversation_id'] == conversationId
    );

    if (existingIndex != -1) {
      // Check if this was a read status update that affects unread count
      final isRead = updatedMessage['is_read'] as bool? ?? false;
      final receiverId = updatedMessage['receiver_id'] as String?;
      final currentUserId = _client.auth.currentUser?.id;

      if (isRead && receiverId == currentUserId) {
        // Message was marked as read, might need to update unread count
        print('Message marked as read, refreshing conversation list...');
        _load(); // Full refresh to get accurate unread counts
      }
    }
  }

  Future<void> _delete(String conversationId) async {
    try {
      await _svc.deleteConversation(conversationId);
      await _load(); // Refresh the list
    } catch (e) {
      print('Error deleting conversation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete conversation: $e')),
        );
      }
    }
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dateTime);

      if (diff.inDays > 0) {
        return '${diff.inDays}d ago';
      } else if (diff.inHours > 0) {
        return '${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes}m ago';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_items.isEmpty
          ? RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.message_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No messages yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Start a conversation with someone!',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            final otherName = (item['other_user_name'] ?? 'User') as String;
            final lastMessage = item['last_message'] ?? '';
            final unread = (item['unread_count'] ?? 0) as int;
            final otherUserId = item['other_user_id'] as String;
            final conversationId = item['conversation_id'] as String;
            final lastMessageTime = item['last_message_time'] as String?;
            final timestamp = _formatTimestamp(lastMessageTime);

            return Dismissible(
              key: ValueKey(conversationId),
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async {
                final shouldDelete = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Conversation'),
                    content: Text('Delete conversation with $otherName?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (shouldDelete == true) {
                  await _delete(conversationId);
                  return true; // Allow dismissal after successful deletion
                }
                return false; // Don't dismiss if cancelled
              },
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    otherName.isNotEmpty ? otherName[0].toUpperCase() : 'U',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  otherName,
                  style: TextStyle(
                    fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unread > 0 ? Colors.black87 : Colors.grey.shade600,
                          fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (timestamp.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        timestamp,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: unread > 0
                    ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
                    : null,
                onTap: () async {
                  // Navigate to chat and refresh list when returning
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        otherUserId: otherUserId,
                        otherUserName: otherName,
                      ),
                    ),
                  );
                  // Refresh the conversation list when returning from chat
                  _load();
                },
              ),
            );
          },
        ),
      )),
    );
  }
}


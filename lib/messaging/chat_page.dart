import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'messaging_service.dart';

class ChatPage extends StatefulWidget {
  final String otherUserId;
  final String? otherUserName;
  final String? rideRequestId;

  const ChatPage({super.key, required this.otherUserId, this.otherUserName, this.rideRequestId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _client = Supabase.instance.client;
  late final MessagingService _svc;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _conversationId;
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _svc = MessagingService(_client);
    _init();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    if (_channel != null) {
      _client.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final me = _client.auth.currentUser?.id;
      if (me == null) {
        setState(() => _loading = false);
        return;
      }

      final convId = await _svc.generateConversationId(me, widget.otherUserId);
      print('Generated conversation ID: $convId');

      final msgs = await _svc.fetchConversationMessages(convId);
      print('Fetched ${msgs.length} messages for conversation $convId');

      setState(() {
        _conversationId = convId;
        _messages = msgs;
        _loading = false;
      });

      // Scroll to bottom after messages load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      // Mark as read
      await _svc.markConversationRead(convId);

      // Subscribe to realtime updates AFTER loading messages
      _subscribeToRealtime(convId);

    } catch (e) {
      print('Error initializing chat: $e');
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load chat: $e')),
        );
      }
    }
  }

  void _subscribeToRealtime(String conversationId) {
    // Remove existing channel first
    if (_channel != null) {
      _client.removeChannel(_channel!);
    }

    // Create a unique channel name
    final channelName = 'messages_conv_${conversationId}_${DateTime.now().millisecondsSinceEpoch}';
    _channel = _client.channel(channelName);

    print('Subscribing to realtime updates for conversation: $conversationId');

    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'conversation_id',
        value: conversationId,
      ),
      callback: (payload) {
        print('Realtime INSERT received: ${payload.newRecord}');
        final newMessage = payload.newRecord;
        if (newMessage != null && mounted) {
          _handleRealtimeMessage(newMessage);
        }
      },
    );

    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'conversation_id',
        value: conversationId,
      ),
      callback: (payload) {
        print('Realtime UPDATE received: ${payload.newRecord}');
        final updatedMessage = payload.newRecord;
        if (updatedMessage != null && mounted) {
          _handleRealtimeMessageUpdate(updatedMessage);
        }
      },
    );

    // Subscribe and handle status
    _channel!.subscribe((status, [ref]) {
      print('Realtime subscription status: $status');
      if (status == RealtimeSubscribeStatus.subscribed) {
        print('Successfully subscribed to realtime updates');
      } else if (status == RealtimeSubscribeStatus.timedOut) {
        print('Realtime subscription timed out, retrying...');
        // Retry subscription after a delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _subscribeToRealtime(conversationId);
        });
      } else if (status == RealtimeSubscribeStatus.closed) {
        print('Realtime subscription closed');
      }
    });
  }

  void _handleRealtimeMessage(Map<String, dynamic> newMessage) {
    // Check if message already exists to avoid duplicates
    final messageId = newMessage['id'];
    final existingIndex = _messages.indexWhere((m) => m['id'] == messageId);

    if (existingIndex == -1) {
      setState(() {
        // Remove any temporary "sending" message if this is our sent message
        final senderId = newMessage['sender_id'];
        final messageText = newMessage['message_text'];

        // Remove temporary sending message
        _messages.removeWhere((m) =>
        m['sender_id'] == senderId &&
            m['message_text'] == messageText &&
            m['is_sending'] == true
        );

        // Add the real message
        _messages.add(newMessage);
      });

      // Auto-scroll if we're near the bottom or this is our message
      final isMyMessage = newMessage['sender_id'] == _client.auth.currentUser?.id;
      if (isMyMessage || _isAtBottom()) {
        _scrollToBottom();
      }

      // Mark as read if it's not our message
      if (!isMyMessage) {
        _markMessageRead(newMessage['id']);
      }
    }
  }

  void _handleRealtimeMessageUpdate(Map<String, dynamic> updatedMessage) {
    final messageId = updatedMessage['id'];
    final messageIndex = _messages.indexWhere((m) => m['id'] == messageId);

    if (messageIndex != -1) {
      setState(() {
        _messages[messageIndex] = updatedMessage;
      });
    }
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    return (maxScroll - currentScroll) < 100; // Within 100 pixels of bottom
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _markMessageRead(String messageId) async {
    try {
      await _client
          .from('messages')
          .update({'is_read': true})
          .eq('id', messageId);
    } catch (e) {
      print('Error marking message as read: $e');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final messageText = text; // Store the text before clearing
    _controller.clear();

    // Add temporary "sending" message immediately for instant UI feedback
    final tempMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'sender_id': _client.auth.currentUser?.id,
      'receiver_id': widget.otherUserId,
      'conversation_id': _conversationId,
      'message_text': messageText,
      'message_type': 'text',
      'is_read': false,
      'is_delivered': false,
      'created_at': DateTime.now().toIso8601String(),
      'is_sending': true, // Custom flag to identify temp messages
    };

    setState(() {
      _messages.add(tempMessage);
    });

    // Scroll to bottom immediately
    _scrollToBottom();

    try {
      await _svc.sendTextMessage(
          toUserId: widget.otherUserId,
          rideRequestId: widget.rideRequestId,
          text: messageText
      );

      print('Message sent successfully: $messageText');

      // The real message will be added via realtime subscription
      // The temporary message will be removed when the real one arrives

    } catch (e) {
      print('Error sending message: $e');

      // Remove the temporary message on error
      setState(() {
        _messages.removeWhere((m) => m['id'] == tempMessage['id']);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
        // Restore the message text if sending failed
        _controller.text = messageText;
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text('This will permanently delete all messages in this conversation.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')
          ),
        ],
      ),
    );

    if (ok == true && _conversationId != null) {
      try {
        await _svc.deleteConversation(_conversationId!);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete conversation: $e')),
          );
        }
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
        title: Text(widget.otherUserName ?? 'Chat'),
        actions: [
          IconButton(
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline)
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
              child: Text(
                'No messages yet. Start the conversation!',
                style: TextStyle(color: Colors.grey),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                final isMe = m['sender_id'] == _client.auth.currentUser?.id;
                final text = m['message_text'] ?? '';
                final timestamp = _formatTimestamp(m['created_at']);
                final isSending = m['is_sending'] == true;
                final isDelivered = m['is_delivered'] == true;

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? (isSending ? Colors.blueAccent.withOpacity(0.7) : Colors.blueAccent)
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (timestamp.isNotEmpty)
                              Text(
                                timestamp,
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              if (isSending)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                  ),
                                )
                              else if (isDelivered)
                                const Icon(
                                  Icons.done,
                                  size: 14,
                                  color: Colors.white70,
                                )
                              else
                                const Icon(
                                  Icons.schedule,
                                  size: 14,
                                  color: Colors.white70,
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      maxLines: null,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
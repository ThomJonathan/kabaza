import 'package:flutter/material.dart';
import 'package:kabanza/Rider/fromV0/rideService.dart';
import 'dart:async';

class MessagesPage extends StatefulWidget {
  final String driverId;
  final String driverName;
  final RideBookingService rideService;
  final String? bookingId;

  const MessagesPage({
    Key? key,
    required this.driverId,
    required this.driverName,
    required this.rideService,
    this.bookingId,
  }) : super(key: key);

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;
  bool _isLoading = true;
  Timer? _messageTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _startMessagePolling();
  }

  void _startMessagePolling() {
    // Poll for new messages every 3 seconds
    _messageTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _loadMessages(showLoading: false);
    });
  }

  Future<void> _loadMessages({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      final messages = await widget.rideService.getMessages(
        driverId: widget.driverId,
        bookingId: widget.bookingId,
      );

      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });

        // Scroll to bottom if new messages
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error loading messages: $e', Colors.red);
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) return;

    String messageText = _messageController.text.trim();
    _messageController.clear();

    setState(() => _isSending = true);

    try {
      bool success = await widget.rideService.sendMessageToDriver(
        driverId: widget.driverId,
        message: messageText,
        bookingId: widget.bookingId,
      );

      if (success) {
        // Reload messages to show the new message
        await _loadMessages(showLoading: false);
      } else {
        _showSnackBar('Failed to send message', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error sending message: $e', Colors.red);
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  String _formatTime(String timestamp) {
    try {
      DateTime dateTime = DateTime.parse(timestamp);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  bool _isMyMessage(Map<String, dynamic> message) {
    // Check if the message sender is the current user
    // This would need to be implemented based on your user identification logic
    return message['sender_id'] != widget.driverId;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                widget.driverName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.driverName,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Driver',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, color: Colors.green),
            onPressed: () {
              _showSnackBar('Calling ${widget.driverName}...', Colors.green);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () => _loadMessages(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.message_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No messages yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a conversation with ${widget.driverName}',
                    style: TextStyle(
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),

          // Typing indicator
          if (_isSending)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sending message...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          // Message input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey, width: 0.2),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    bool isMe = _isMyMessage(message);
    String timestamp = message['created_at'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                widget.driverName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Theme.of(context).primaryColor : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message['message'] ?? '',
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                  if (timestamp.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(timestamp),
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
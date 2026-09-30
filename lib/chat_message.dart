enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.reasoningContent,
  });

  final ChatRole role;
  final String content;
  final String? reasoningContent;
}

import 'package:chaty/utils/extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'message.dart'; // Import MessageType from Message model

/// Represents a summary of a chat, including the last message, users involved,
/// and unread message counts.
class ChatSummary {
  /// Unique identifier for the chat.
  final String chatId;

  /// The last message sent in the chat.
  final String lastMessage;

  /// The type of the last message (text, image, audio, etc.).
  final MessageType lastMessageType;

  /// The time when the last message was sent.
  final DateTime lastMessageTime;

  /// List of user IDs involved in the chat.
  final List<String> users;

  /// The ID of the other user in the chat (not the current user).
  final String otherUserId;

  /// The ID of the user who sent the last message.
  final String lastMessageSenderId;

  /// A map containing the count of unread messages for each user in the chat.
  final Map<String, int> unreadMessageCount;

  /// Optional fields for displaying other user's name and image URL.
  String? otherUserName;

  /// Optional field for the other user's profile image URL.
  String? otherUserImageUrl;

  /// Creates a new ChatSummary instance.
  ChatSummary({
    required this.chatId,
    required this.lastMessage,
    required this.lastMessageType,
    required this.lastMessageTime,
    required this.users,
    required this.otherUserId,
    required this.lastMessageSenderId,
    required this.unreadMessageCount, // 🔥 Initialize unreadCount\
    this.otherUserName,
    this.otherUserImageUrl,
  });

  /// Factory constructor to create a ChatSummary from Firestore data.
  /// The [currentUserId] is used to determine the other user's ID in the chat.
  factory ChatSummary.fromMap(Map<String, dynamic> map, String currentUserId) {
    try {
      final otherId = (map['users'] is List &&
              (map['users'] as List).isNotEmpty)
          ? (map['users'] as List<dynamic>)
              .map((e) => e.toString())
              .firstWhere((id) => id != currentUserId, orElse: () => "Unknown")
          : "Unknown";

      return ChatSummary(
        chatId: map['chatId'] ?? "",
        lastMessage: map['lastMessage'] ?? "No message",
        lastMessageSenderId: map['lastMessageSender'] ?? "Unknown",
        lastMessageType: MessageType.values.any((e) =>
                e.toString().split('.').last ==
                (map['lastMessageType'] ?? "text"))
            ? MessageType.values.firstWhere(
                (e) =>
                    e.toString().split('.').last ==
                    (map['lastMessageType'] ?? "text"),
              )
            : MessageType.text,
        lastMessageTime:
            (map['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
        users: List<String>.from(map['users'] ?? []),
        otherUserId: otherId,
        otherUserName: map['userDetails']?[otherId]?['name'],
        otherUserImageUrl: map['userDetails']?[otherId]?['imageUrl'],
        unreadMessageCount: Map<String, int>.from(map['unreadMessageCount'] ??
            {}), // 🔥 Fetch unread count from Firestore
      );
    } catch (e) {
      e.log("❌ Error converting Firestore data to ChatSummary");
      return ChatSummary(
        chatId: "",
        lastMessage: "Error loading message",
        lastMessageType: MessageType.text,
        lastMessageTime: DateTime.now(),
        users: [],
        otherUserId: "Unknown",
        lastMessageSenderId: 'Unknown',
        unreadMessageCount: {}, // 🔥 Default unread count to 0
      );
    }
  }

  /// Convert model to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'lastMessage': lastMessage,
      'lastMessageType': lastMessageType.toString().split('.').last,
      'lastMessageTime': lastMessageTime,
      'users': users,
      'lastMessageSender': lastMessageSenderId,
      'unreadMessageCount':
          unreadMessageCount, // 🔥 Store unreadCount in Firestore
      'userDetails': {
        for (var userId in users)
          userId: {
            'name': userId == otherUserId ? otherUserName : null,
            'imageUrl': userId == otherUserId ? otherUserImageUrl : null,
          }
      },
    };
  }
}

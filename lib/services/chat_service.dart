import 'package:chaty/models/chat_summary.dart';
import 'package:chaty/services/storage_services.dart';
import 'package:chaty/utils/extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message.dart';

class ChatService {
  // Singleton instance
  static final ChatService instance = ChatService._internal();

  // Private constructor
  ChatService._internal();

  // Factory constructor to return the singleton instance
  factory ChatService() {
    return instance;
  }
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Send a new message
  Future<void> sendMessage(Message message) async {
    final chatId = getChatId(message.senderId, message.receiverId);
    DocumentReference messageRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(message.messageId);

    await messageRef.set(message.toMap());

    // Determine last message text based on type
    String lastMessageText = message.text.isNotEmpty
        ? message.text
        : (message.type == MessageType.image
            ? "📷 Image"
            : message.type == MessageType.audio
                ? "🎵 Audio"
                : message.type == MessageType.video
                    ? "📹 Video"
                    : "📎 File");

    // Update chat summary
    await _firestore.collection('chats').doc(chatId).set({
      'lastMessage': lastMessageText,
      'lastMessageType': message.type.toString(),
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSender': message.senderId, // Store sender's ID
      'users': [message.senderId, message.receiverId],
      'unreadCount': FieldValue.increment(1), // ✅ Increase unread count
    }, SetOptions(merge: true));
  }

  Future<void> updateLastSeen(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).set(
        {'lastSeen': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e) {
      e.log("Error updating last seen:");
    }
  }

  Stream<Timestamp?> getLastSeen(String userId) {
    // Retrieve the updated document to get the lastSeen timestamp
    Stream<DocumentSnapshot<Map<String, dynamic>>> userDoc =
        _firestore.collection('users').doc(userId).snapshots();
    return userDoc.map((snapshot) {
      if (snapshot.exists) {
        return snapshot.data()!['lastSeen'] as Timestamp;
      }
      return null;
    });
  }

  late QueryDocumentSnapshot<Map<String, dynamic>> lastDocument;

  /// Fetch messages in real-time
  Stream<List<Message>> getMessages(String chatId) {
    print(chatId);
    final snap = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return snap.map((snapshot) {
      lastDocument = snapshot.docs.last;
      return snapshot.docs.map((doc) => Message.fromMap(doc.data())).toList();
    });
  }

  int initialLimit = 5;
  Future<List<Message>> fetchMessages(String chatId,
      {Message? lastMessage}) async {
    Query query = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(initialLimit);

    if (lastMessage != null) {
      query = query.startAfter([lastMessage.toMap()['timestamp']]);
    }

    QuerySnapshot querySnapshot = await query.get();

    print("🔥 Fetching messages for chatId: $chatId");
    print("🔥 Last Timestamp: ${lastMessage?.timestamp}");
    print("🔥 Query Retrieved Messages: ${querySnapshot.docs.length}");

    // Print all retrieved message timestamps
    for (var doc in querySnapshot.docs) {
      print(
          "🔥 Message Timestamp: ${(doc.data() as Map<String, dynamic>)['timestamp']}");
    }

    List<Message> messages = querySnapshot.docs
        .map((doc) => Message.fromMap(doc.data() as Map<String, dynamic>))
        .toList();

    return messages;
  }

  Stream<List<Message>> streamLatestMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId.log('chatId'))
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(initialLimit) // Stream the latest 20 messages
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Message.fromMap(doc.data().log('doc')))
            .toList());
  }

  /// Update message status (delivered, unread, read)
  Future<void> updateMessageStatus(
      String chatId, String messageId, MessageStatus status) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'status': status.toString().split('.').last});
  }

  /// Generate a unique chat ID based on user IDs
  String getChatId(String user1, String user2) {
    /// Generates a unique identifier for a chat between two users based on their hash codes.
    ///
    /// The identifier is created by comparing the hash codes of the two user IDs.
    /// If the hash code of `user1` is less than or equal to the hash code of `user2`,
    /// the identifier is formatted as `"$user1_$user2"`. Otherwise, it is formatted
    /// as `"$user2_$user1"`.
    ///
    /// This ensures that the order of the user IDs does not affect the generated identifier,
    /// making it consistent regardless of the order in which the users are provided.
    ///
    /// Returns:
    /// A string representing the unique identifier for the chat.
    return user1.hashCode <= user2.hashCode
        ? "$user1\_$user2"
        : "$user2\_$user1";
  }

  final StorageService _storageService = StorageService();

  /// Delete a message and its associated media (if any)
  Future<void> deleteMessage(String chatId, String messageId) async {
    try {
      DocumentReference messageRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);

      DocumentSnapshot messageSnapshot = await messageRef.get();

      if (messageSnapshot.exists) {
        Message message =
            Message.fromMap(messageSnapshot.data() as Map<String, dynamic>);

        // If the message has a media URL, delete the media file
        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) {
          await _storageService.deleteMedia(message.mediaUrl!);
        }

        // Delete the message from Firestore
        await messageRef.update({
          'isDeleted': true,
        });
        ;
      }
    } catch (e) {
      print('Error deleting message: $e');
    }
  }

  /// Mark all unread messages as "read" when the recipient opens the chat
  Future<void> markMessagesAsRead(String chatId, String receiverId) async {
    QuerySnapshot messages = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('receiverId',
            isEqualTo: receiverId) // Messages meant for this user
        .where('status', isEqualTo: 'unread')
        .get();

    for (var doc in messages.docs) {
      doc.reference.update({'status': 'read'});
    }

    // ✅ Reset unread count to 0 when user opens chat
    FirebaseFirestore.instance.collection('chats').doc(chatId).update({
      'unreadCount': 0,
    });
  }

  /// Update typing status in Firestore
  Future<void> updateTypingStatus(
      String chatId, String userId, bool isTyping) async {
    await _firestore.collection('chats').doc(chatId).update({
      'typingStatus.$userId': isTyping,
    });
  }

  /// Listen to typing status changes
  Stream<Map<String, dynamic>?> getTypingStatus(String chatId) {
    return _firestore.collection('chats').doc(chatId).snapshots().map(
      (snapshot) {
        if (snapshot.exists && snapshot.data()!.containsKey('typingStatus')) {
          return snapshot.data()!['typingStatus'] as Map<String, dynamic>;
        }
        return null;
      },
    );
  }

  Stream<List<ChatSummary>> getUserChats(String userId) {
    return _firestore
        .collection('chats')
        .where('users', arrayContainsAny: [userId])
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data().log('snapshot');

            return ChatSummary.fromMap(
              data,
              userId,
            );
          }).toList();
        });
  }
}

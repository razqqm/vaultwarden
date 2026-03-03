import 'dart:async';
import 'dart:typed_data';

import 'package:msgpack_dart/msgpack_dart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connects to the server's SignalR notifications hub to receive
/// real-time auth request notifications.
///
/// Protocol: SignalR with MessagePack serialization.
/// Fallback: polling (handled by the provider layer).
class NotificationService {
  WebSocketChannel? _channel;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  final _controller = StreamController<int>.broadcast();

  String? _lastServerUrl;
  String? _lastAccessToken;
  bool _paused = false;

  /// Emits notification type IDs (15 = AuthRequest, 16 = AuthRequestResponse).
  Stream<int> get onNotification => _controller.stream;

  bool get isConnected => _channel != null;

  /// Connect to /notifications/hub with SignalR handshake.
  Future<void> connect(String serverUrl, String accessToken) async {
    _lastServerUrl = serverUrl;
    _lastAccessToken = accessToken;
    _paused = false;
    await _doConnect(serverUrl, accessToken);
  }

  Future<void> _doConnect(String serverUrl, String accessToken) async {
    _closeChannel();

    final wsScheme = serverUrl.startsWith('https') ? 'wss' : 'ws';
    final host = serverUrl
        .replaceFirst('https://', '')
        .replaceFirst('http://', '')
        .replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$wsScheme://$host/notifications/hub?access_token=$accessToken',
    );

    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      // SignalR handshake: send JSON protocol spec with record separator
      _channel!.sink.add('{"protocol":"messagepack","version":1}\x1e');

      _channel!.stream.listen(
        _handleMessage,
        onError: (_) => _onDisconnected(),
        onDone: () => _onDisconnected(),
      );

      // Keep-alive ping every 30 seconds (SignalR type 6)
      _keepAliveTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _sendKeepAlive(),
      );
    } catch (e) {
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    _closeChannel();
    // Auto-reconnect after 5s unless paused
    if (!_paused && _lastServerUrl != null && _lastAccessToken != null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 5), () {
        if (!_paused) _doConnect(_lastServerUrl!, _lastAccessToken!);
      });
    }
  }

  void _closeChannel() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void disconnect() {
    _paused = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeChannel();
  }

  /// Pause WebSocket (app going to background).
  void pause() {
    _paused = true;
    _reconnectTimer?.cancel();
    _closeChannel();
  }

  /// Resume WebSocket (app returning to foreground).
  void resume() {
    _paused = false;
    if (_lastServerUrl != null && _lastAccessToken != null) {
      _doConnect(_lastServerUrl!, _lastAccessToken!);
    }
  }

  /// Update access token (after refresh).
  void updateToken(String newAccessToken) {
    _lastAccessToken = newAccessToken;
    if (!_paused && _lastServerUrl != null) {
      _doConnect(_lastServerUrl!, newAccessToken);
    }
  }

  void _handleMessage(dynamic message) {
    if (message is String) {
      // Handshake response: "{}\x1e" — ignore
      return;
    }

    if (message is! List<int>) return;

    try {
      // SignalR binary frame: length-prefix + MessagePack payload
      // Skip the variable-length prefix to find the MessagePack data
      final bytes = Uint8List.fromList(message);
      final payload = _extractMessagePackPayload(bytes);
      if (payload == null) return;

      final decoded = deserialize(payload);
      if (decoded is! List || decoded.isEmpty) return;

      // SignalR invocation: [type, headers, invocationId, target, arguments]
      // Type 1 = Invocation
      final msgType = decoded[0];
      if (msgType != 1 || decoded.length < 5) return;

      final args = decoded[4];
      if (args is! List || args.isEmpty) return;

      final notification = args[0];
      if (notification is Map) {
        final type = notification['Type'] ?? notification['type'];
        if (type is int) {
          _controller.add(type);
        }
      }
    } catch (_) {
      // Malformed message — ignore
    }
  }

  Uint8List? _extractMessagePackPayload(Uint8List bytes) {
    // SignalR binary protocol: varint length prefix followed by MessagePack
    // Each byte: 7 data bits, MSB = continuation flag
    var offset = 0;
    var length = 0;
    var shift = 0;

    while (offset < bytes.length) {
      final b = bytes[offset];
      length |= (b & 0x7F) << shift;
      offset++;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }

    if (offset + length > bytes.length) return null;
    return Uint8List.sublistView(bytes, offset, offset + length);
  }

  void _sendKeepAlive() {
    if (_channel == null) return;
    try {
      // SignalR ping: MessagePack [6] with varint length prefix
      final pingPayload = serialize([6]);
      final lengthPrefix = _encodeVarint(pingPayload.length);
      final frame = Uint8List.fromList([...lengthPrefix, ...pingPayload]);
      _channel!.sink.add(frame);
    } catch (_) {
      // Connection lost
      disconnect();
    }
  }

  Uint8List _encodeVarint(int value) {
    final bytes = <int>[];
    while (value > 0x7F) {
      bytes.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    bytes.add(value & 0x7F);
    return Uint8List.fromList(bytes);
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}

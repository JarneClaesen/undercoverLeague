import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus { disconnected, connecting, connected, reconnecting }

/// A rejected command. [code] is one of the server's error codes:
/// notFound, exists, inProgress, nameTaken, notHost, expired, invalid.
class GameError implements Exception {
  final String code;
  final String message;
  const GameError(this.code, this.message);

  @override
  String toString() => 'GameError($code): $message';
}

/// An emoji thrown by a spectator or eliminated player; ephemeral, never
/// part of the [Lobby] view.
class Reaction {
  final String playerName;
  final String emoji;
  const Reaction({required this.playerName, required this.emoji});

  @override
  String toString() => 'Reaction($playerName $emoji)';
}

class Session {
  final String token;
  final String lobbyId;
  final String playerName;
  final bool isHost;
  const Session({required this.token, required this.lobbyId, required this.playerName, required this.isHost});
}

/// The single WebSocket to the game server. Screens never own it: it is
/// opened by create/join, kept alive across navigation, resumed with the
/// session token when the socket drops, and closed by an explicit leave or
/// when the lobby goes away.
class GameConnection {
  GameConnection._();
  static final GameConnection instance = GameConnection._();

  /// Server URL. `--dart-define=UNDERCOVER_WS_URL=ws://localhost:8080/ws`
  /// overrides it for local development. On the web the default is the
  /// origin the page was served from, since the server hosts the web build.
  static String get wsUrl {
    const override = String.fromEnvironment('UNDERCOVER_WS_URL');
    if (override.isNotEmpty) return override;
    if (kIsWeb) {
      // Built from parts: `Uri.replace` keeps the page's query (`?lobby=`).
      final base = Uri.base;
      return Uri(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '/ws',
      ).toString();
    }
    return 'wss://undercover.jarneclaesen.be/ws';
  }

  static const _requestTimeout = Duration(seconds: 10);
  static const _reconnectDelays = [1, 2, 4, 8, 16, 16, 16];

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  int _nextReqId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  bool _leaving = false;
  bool _reconnecting = false;

  final _lobbyController = StreamController<Lobby?>.broadcast();
  final _errorController = StreamController<GameError>.broadcast();
  final _reactionController = StreamController<Reaction>.broadcast();

  /// Latest view of the lobby; `null` means it was closed or lost. New
  /// listeners do not get a replay, so pass [current] as `initialData`.
  Stream<Lobby?> get lobby => _lobbyController.stream;
  Lobby? current;

  /// Server errors not tied to a request (e.g. an action that was no longer
  /// allowed by the time it arrived).
  Stream<GameError> get errors => _errorController.stream;

  /// Reactions from everyone in the room, including the viewer's own.
  Stream<Reaction> get reactions => _reactionController.stream;

  final ValueNotifier<ConnectionStatus> status = ValueNotifier(ConnectionStatus.disconnected);
  Session? session;

  /// Why the last session ended: 'closed' (host left), 'kicked' (the host
  /// removed this player), 'expired' (could not resume) or 'unreachable'
  /// (gave up reconnecting). Cleared by [takeCloseReason].
  String? _lastCloseReason;

  String? takeCloseReason() {
    final r = _lastCloseReason;
    _lastCloseReason = null;
    return r;
  }

  Future<void> connect() async {
    if (_channel != null) return;
    if (status.value == ConnectionStatus.disconnected) status.value = ConnectionStatus.connecting;
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    try {
      await channel.ready;
    } catch (_) {
      if (status.value == ConnectionStatus.connecting) status.value = ConnectionStatus.disconnected;
      rethrow;
    }
    _channel = channel;
    _subscription = channel.stream.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone());
    // While resuming, stay "reconnecting" until the server accepts the token.
    if (!_reconnecting) status.value = ConnectionStatus.connected;
  }

  /// Sends a command and waits for the matching `joined` or `error` event.
  Future<Map<String, dynamic>> request(Map<String, dynamic> command) async {
    await connect();
    final reqId = _nextReqId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[reqId] = completer;
    _send({...command, 'reqId': reqId});
    return completer.future.timeout(_requestTimeout, onTimeout: () {
      _pending.remove(reqId);
      throw TimeoutException('No reply from server');
    });
  }

  /// Fire-and-forget command; a rejection arrives on [errors].
  void send(Map<String, dynamic> command) => _send(command);

  void _send(Map<String, dynamic> command) {
    final channel = _channel;
    if (channel == null) {
      throw const GameError('disconnected', 'Not connected to the server.');
    }
    channel.sink.add(jsonEncode(command));
  }

  /// Leaves the lobby and closes the socket. Safe to call when not connected.
  Future<void> leave() async {
    final channel = _channel;
    session = null;
    current = null;
    if (channel == null) {
      status.value = ConnectionStatus.disconnected; // also stops a reconnect loop
      return;
    }
    _leaving = true;
    try {
      channel.sink.add(jsonEncode({'type': 'leave'}));
      await channel.sink.close();
    } catch (_) {
      // The socket may already be gone; nothing to clean up server-side then.
    } finally {
      _dropChannel();
      _leaving = false;
      status.value = ConnectionStatus.disconnected;
    }
  }

  void _onMessage(dynamic data) {
    final event = jsonDecode(data as String) as Map<String, dynamic>;
    final reqId = event['reqId'] as int?;
    switch (event['type']) {
      case 'joined':
        session = Session(
          token: event['token'] as String,
          lobbyId: event['lobbyId'] as String,
          playerName: event['playerName'] as String,
          isHost: event['isHost'] as bool? ?? false,
        );
        _pending.remove(reqId)?.complete(event);
      case 'error':
        final error = GameError(event['code'] as String? ?? 'internal', event['message'] as String? ?? '');
        final pending = _pending.remove(reqId);
        if (pending != null) {
          pending.completeError(error);
        } else {
          _errorController.add(error);
        }
      case 'lobby':
        final lobby = Lobby.fromJson(event['lobby'] as Map<String, dynamic>);
        // A view from before a reconnect can still be in flight; ignore it.
        if (current != null && current!.id == lobby.id && lobby.version < current!.version) return;
        current = lobby;
        _lobbyController.add(lobby);
      case 'lobbyClosed':
        _lastCloseReason = 'closed';
        _end();
      case 'kicked':
        _lastCloseReason = 'kicked';
        _end();
      case 'reaction':
        final emoji = event['emoji'] as String? ?? '';
        if (emoji.isEmpty) return;
        _reactionController.add(Reaction(playerName: event['playerName'] as String? ?? '', emoji: emoji));
    }
  }

  void _onDone() {
    if (_channel == null) return; // already handled
    _dropChannel();
    _failPending(const GameError('disconnected', 'Connection lost.'));
    if (_leaving || _reconnecting) return;
    if (session == null) {
      status.value = ConnectionStatus.disconnected;
      return;
    }
    _reconnect();
  }

  Future<void> _reconnect() async {
    _reconnecting = true;
    status.value = ConnectionStatus.reconnecting;
    try {
      for (final seconds in _reconnectDelays) {
        await Future<void>.delayed(Duration(seconds: seconds));
        final s = session;
        if (s == null || _leaving) return; // left while waiting
        try {
          await request({'type': 'resume', 'lobbyId': s.lobbyId, 'token': s.token});
          status.value = ConnectionStatus.connected;
          return;
        } on GameError catch (e) {
          if (e.code == 'expired' || e.code == 'notFound') {
            _lastCloseReason = 'expired';
            _end();
            return;
          }
        } catch (_) {
          // Server not reachable yet; try again after the next delay.
        }
        _closeChannel();
      }
      _lastCloseReason = 'unreachable';
      _end();
    } finally {
      _reconnecting = false;
    }
  }

  /// The session is over: tell the screens (null lobby) and drop the socket.
  void _end() {
    session = null;
    current = null;
    _failPending(const GameError('disconnected', 'Connection closed.'));
    _lobbyController.add(null);
    _closeChannel();
    status.value = ConnectionStatus.disconnected;
  }

  void _closeChannel() {
    final channel = _channel;
    _dropChannel();
    channel?.sink.close().catchError((_) {});
  }

  void _dropChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
  }

  void _failPending(GameError error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }
}

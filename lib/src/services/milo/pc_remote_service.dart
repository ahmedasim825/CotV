import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/pc_command.dart';
import 'milo_credentials.dart';

/// Sends [PcCommand]s to the `milo_pc_agent.py` process on the Windows
/// machine over the local network.
///
/// Every call carries a bearer token the agent checks before doing
/// anything, and every failure comes back as a [PcCommandResult] rather
/// than an exception. That is not error swallowing: the message is what
/// the receipt shows and what the model is told, so an unreachable laptop
/// produces "your PC did not answer" in the reply instead of an aborted
/// turn with no explanation.
class PcRemoteService {
  PcRemoteService({required http.Client httpClient}) : _http = httpClient;

  /// The agent is on the same Wi-Fi and answers in milliseconds when it is
  /// awake. A longer wait would only be spent on a machine that is asleep,
  /// which is the case worth reporting quickly.
  static const Duration timeout = Duration(seconds: 6);

  final http.Client _http;

  Future<PcCommandResult> execute(
    PcCommand command, {
    required PcAgentConfig agent,
  }) async {
    try {
      final response = await _http
          .post(
            agent.endpoint(command.kind.path),
            headers: {
              'Authorization': 'Bearer ${agent.token}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(command.toJson()),
          )
          .timeout(timeout);

      final body = _decode(response.body);

      if (response.statusCode == 200) {
        return PcCommandResult.success(
          command,
          body?['message'] as String? ?? 'Done on PC.',
        );
      }

      return PcCommandResult.failure(
        command,
        _rejection(response.statusCode, body, agent),
      );
    } on TimeoutException {
      return PcCommandResult.failure(
        command,
        'Your PC did not answer within ${timeout.inSeconds}s. It may be '
        'asleep, or the agent may not be running.',
      );
    } on http.ClientException catch (e) {
      // Also covers the socket failures IOClient re-wraps: host down,
      // wrong port, or the phone being on a different network.
      return PcCommandResult.failure(
        command,
        'Could not reach ${agent.baseUrl.host}: ${e.message}',
      );
    }
  }

  /// FastAPI puts its own errors under `detail`; the agent's handlers put
  /// theirs under `message`. Take whichever is present.
  String _rejection(
    int status,
    Map<String, dynamic>? body,
    PcAgentConfig agent,
  ) {
    final detail = body?['message'] ?? body?['detail'];
    switch (status) {
      case 401:
      case 403:
        return 'The agent rejected the token. Check it matches the one in '
            'the agent config.';
      case 404:
        return detail is String
            ? detail
            : 'The agent has no endpoint for this command.';
      default:
        return detail is String
            ? detail
            : 'The agent returned $status.';
    }
  }

  Map<String, dynamic>? _decode(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      // Something other than the agent answered on that port.
      return null;
    }
  }
}

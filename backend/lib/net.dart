// The HTTP client for calls to banks, Stripe, the stores and Parqet: a call
// that gets no answer within 30 s fails instead of holding its request open.
import 'dart:async';

import 'package:http/http.dart' as http;

class _TimeoutClient extends http.BaseClient {
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(const Duration(seconds: 30));
}

final http.Client net = _TimeoutClient();

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ulink_emulator/ulink_emulator_models.dart';

class UlinkEmulatorService {
  UlinkEmulatorService({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _getUrlUri = Uri.parse(
    'https://ulinkwebapi.ultratech.ind.in/api/GetURL',
  );

  final http.Client _client;
  String? _apiHttpsBaseUrl;

  Future<UlinkUrlResponse> getUrl() async {
    final json = await _getJson(_getUrlUri);
    final response = UlinkUrlResponse.fromJson(json);
    if (response.result == 1 && response.urlApiHttps.isNotEmpty) {
      _apiHttpsBaseUrl = response.urlApiHttps;
    }
    return response;
  }

  Future<UlinkSettingsResponse> getUlinkSettings(String uCode) async {
    final baseUrl = _apiHttpsBaseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw StateError('GetURL must succeed before requesting Ulink settings.');
    }
    final uri = _endpoint('GetUlinkSettings').replace(
      queryParameters: <String, String>{'Type': 'json', 'UCode': uCode},
    );
    return UlinkSettingsResponse.fromJson(await _getJson(uri));
  }

  Future<UlinkPostRecordResponse> postRecord(
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post(
      _endpoint('PostRecord'),
      headers: const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(payload),
    );
    return UlinkPostRecordResponse.fromJson(_decodeResponse(response));
  }

  Uri _endpoint(String path) {
    final baseUrl = _apiHttpsBaseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw StateError('GetURL must succeed before sending records.');
    }
    return Uri.parse(baseUrl.endsWith('/') ? '$baseUrl$path' : '$baseUrl/$path');
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri);
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('The Ulink API returned a non-object JSON response.');
    }
    final json = Map<String, dynamic>.from(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UlinkApiException(
        json['Message']?.toString() ?? 'HTTP ${response.statusCode}',
      );
    }
    return json;
  }

  void dispose() => _client.close();
}

class UlinkApiException implements Exception {
  const UlinkApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

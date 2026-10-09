import 'dart:convert';

import 'package:http/http.dart' as http;

class DriveApiException implements Exception {
  DriveApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'Drive API $statusCode: $message';
}

class DriveFile {
  DriveFile.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String? ?? '',
        modifiedTime = DateTime.tryParse(json['modifiedTime'] as String? ?? ''),
        resourceKey = json['resourceKey'] as String?,
        webViewLink = json['webViewLink'] as String?;

  final String id;
  final String name;
  final DateTime? modifiedTime;
  final String? resourceKey;
  final String? webViewLink;
}

/// The narrow Drive operations used by Carta Drive. Tokens are requested for
/// each call so the Google Sign-In plugin can refresh expired access tokens.
class DriveApi {
  DriveApi({
    required Future<String> Function() accessToken,
    Future<void> Function(String token)? invalidateAccessToken,
    http.Client? client,
    this.publicApiKey = const String.fromEnvironment('DRIVE_PUBLIC_API_KEY'),
  })  : _accessToken = accessToken,
        _invalidateAccessToken = invalidateAccessToken,
        _client = client ?? http.Client();

  static final Uri _filesUrl =
      Uri.parse('https://www.googleapis.com/drive/v3/files');
  static final Uri _uploadUrl =
      Uri.parse('https://www.googleapis.com/upload/drive/v3/files');

  Uri _itemUrl(Uri base, String id,
          {String? suffix, Map<String, String>? query}) =>
      base.replace(
        pathSegments: [...base.pathSegments, id, if (suffix != null) suffix],
        queryParameters: query,
      );

  final Future<String> Function() _accessToken;
  final Future<void> Function(String token)? _invalidateAccessToken;
  final http.Client _client;
  final String publicApiKey;

  void close() => _client.close();

  Future<http.Response> _request(
    Future<http.Response> Function(Map<String, String> headers) send, {
    String? contentType,
  }) async {
    final token = await _accessToken();
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      if (contentType != null) 'Content-Type': contentType,
    };
    var response = await send(headers);
    if (response.statusCode == 401 && _invalidateAccessToken != null) {
      await _invalidateAccessToken!(token);
      headers['Authorization'] = 'Bearer ${await _accessToken()}';
      response = await send(headers);
    }
    return response;
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DriveApiException(
          response.statusCode, utf8.decode(response.bodyBytes));
    }
  }

  Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

  Future<List<DriveFile>> listAppFiles() async {
    final files = <DriveFile>[];
    String? pageToken;
    do {
      final uri = _filesUrl.replace(queryParameters: {
        'spaces': 'appDataFolder',
        'q': 'trashed = false',
        'pageSize': '1000',
        'fields':
            'nextPageToken,files(id,name,modifiedTime,resourceKey,webViewLink)',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final response =
          await _request((headers) => _client.get(uri, headers: headers));
      _check(response);
      final body = _json(response);
      for (final item in body['files'] as List<dynamic>? ?? []) {
        files.add(DriveFile.fromJson(item as Map<String, dynamic>));
      }
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null);
    return files;
  }

  Future<Map<String, dynamic>> readJson(String id,
      {String? resourceKey}) async {
    final uri = _itemUrl(_filesUrl, id, query: {'alt': 'media'});
    final response = await _request((headers) {
      if (resourceKey != null) {
        headers['X-Goog-Drive-Resource-Keys'] = '$id/$resourceKey';
      }
      return _client.get(uri, headers: headers);
    });
    _check(response);
    return _json(response);
  }

  /// Link-shared libraries are intentionally public. Reading them with an API
  /// key avoids requesting access to the reader's entire Google Drive.
  Future<Map<String, dynamic>> readPublicJson(String id,
      {String? resourceKey}) async {
    if (publicApiKey.isEmpty) {
      throw StateError('DRIVE_PUBLIC_API_KEY is required for shared libraries');
    }
    final uri = _itemUrl(_filesUrl, id, query: {'alt': 'media'});
    final response = await _client.get(uri, headers: {
      'X-Goog-Api-Key': publicApiKey,
      if (resourceKey != null) 'X-Goog-Drive-Resource-Keys': '$id/$resourceKey',
    });
    _check(response);
    return _json(response);
  }

  Future<DriveFile> createJson(String name, Map<String, dynamic> data,
      {bool appData = true}) async {
    final boundary = 'cartadrive_${DateTime.now().microsecondsSinceEpoch}';
    final metadata = {
      'name': name,
      'mimeType': 'application/json',
      if (appData) 'parents': ['appDataFolder'],
    };
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(metadata)}\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(data)}\r\n'
        '--$boundary--\r\n';
    final uri = _uploadUrl.replace(queryParameters: {
      'uploadType': 'multipart',
      'fields': 'id,name,modifiedTime,resourceKey,webViewLink',
    });
    final response = await _request(
      (headers) => _client.post(uri, headers: headers, body: utf8.encode(body)),
      contentType: 'multipart/related; boundary=$boundary',
    );
    _check(response);
    return DriveFile.fromJson(_json(response));
  }

  Future<void> updateJson(String id, Map<String, dynamic> data) async {
    final uri = _itemUrl(_uploadUrl, id, query: {'uploadType': 'media'});
    final response = await _request(
      (headers) => _client.patch(uri, headers: headers, body: jsonEncode(data)),
      contentType: 'application/json; charset=UTF-8',
    );
    _check(response);
  }

  Future<void> deleteFile(String id) async {
    final response = await _request(
        (headers) => _client.delete(_itemUrl(_filesUrl, id), headers: headers));
    _check(response);
  }

  Future<DriveFile> getMetadata(String id) async {
    final uri = _itemUrl(_filesUrl, id,
        query: {'fields': 'id,name,modifiedTime,resourceKey,webViewLink'});
    final response =
        await _request((headers) => _client.get(uri, headers: headers));
    _check(response);
    return DriveFile.fromJson(_json(response));
  }

  Future<void> shareByLink(String id) async {
    final uri = _itemUrl(_filesUrl, id, suffix: 'permissions');
    final response = await _request(
      (headers) => _client.post(uri,
          headers: headers,
          body: jsonEncode({
            'type': 'anyone',
            'role': 'reader',
            'allowFileDiscovery': false,
          })),
      contentType: 'application/json',
    );
    _check(response);
  }
}

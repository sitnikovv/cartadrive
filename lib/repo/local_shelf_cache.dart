import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../model/cartabook.dart';
import '../model/cartalibrary.dart';
import '../model/cartaserver.dart';

class CachedShelf {
  CachedShelf(this.books, this.servers, this.libraries);

  final List<CartaBook> books;
  final List<CartaServer> servers;
  final List<CartaLibrary> libraries;
}

/// An app-private, account-specific copy of the last successful Drive sync.
/// WebDAV credentials and Google tokens are never written to this file.
class LocalShelfCache {
  LocalShelfCache(this.directory);

  final Directory directory;
  Future<void> _writes = Future.value();

  File _file(String uid) {
    final id = sha256.convert(utf8.encode(uid)).toString();
    return File('${directory.path}/$id.json');
  }

  dynamic _withoutCredentials(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (entry.key != 'username' &&
              entry.key != 'password' &&
              entry.key != 'credential')
            entry.key as String: _withoutCredentials(entry.value),
      };
    }
    if (value is List) return value.map(_withoutCredentials).toList();
    return value;
  }

  Future<CachedShelf?> load(String uid) async {
    final file = _file(uid);
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString(encoding: utf8))
        as Map<String, dynamic>;
    if (data['version'] != 1) return null;
    final books = (data['books'] as List<dynamic>)
        .map((item) => CartaBook.fromFirestore(item as Map<String, dynamic>))
        .toList();
    final servers = (data['servers'] as List<dynamic>)
        .map((item) => CartaServer.fromFirestore(item as Map<String, dynamic>))
        .toList();
    final libraries = (data['libraries'] as List<dynamic>).map((item) {
      final json = item as Map<String, dynamic>;
      final library = CartaLibrary.fromFirestore(json['id'] as String, json);
      library.signedUp = true;
      return library;
    }).toList();
    return CachedShelf(books, servers, libraries);
  }

  Future<void> save(String uid, CachedShelf shelf) {
    final previous = _writes;
    final write = () async {
      await previous;
      await directory.create(recursive: true);
      final file = _file(uid);
      final temporary =
          File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
      final data = _withoutCredentials({
        'version': 1,
        'books': shelf.books.map((book) => book.toFirestore()).toList(),
        'servers': shelf.servers.map((server) => server.toFirestore()).toList(),
        'libraries':
            shelf.libraries.map((library) => library.toFirestore()).toList(),
      });
      try {
        await temporary.writeAsString(jsonEncode(data),
            encoding: utf8, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }();
    _writes = write.catchError((Object _) {});
    return write;
  }
}

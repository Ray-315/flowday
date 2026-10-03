import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'repository.dart';

class AccountRepository extends JsonRepository {
  AccountRepository(Directory root, Uri server, String userId)
    : super(
        Directory(
          '${root.path}/accounts/${sha256.convert(utf8.encode('$server\n$userId'))}',
        ),
      );

  File get _metadata => File('${directory.path}/sync.json');
  Future<({int? version, String? json})> loadBaseline() async {
    if (!await _metadata.exists()) return (version: null, json: null);
    try {
      final value =
          jsonDecode(await _metadata.readAsString()) as Map<String, dynamic>;
      final version = value['version'];
      final json = value['json'];
      if (version is! int || version < 0 || json is! String) {
        return (version: null, json: null);
      }
      return (version: version, json: json);
    } on FormatException {
      return (version: null, json: null);
    } on TypeError {
      return (version: null, json: null);
    }
  }

  Future<void> saveBaseline(int version, String json) async {
    await directory.create(recursive: true);
    final temporary = File('${_metadata.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'version': version, 'json': json}),
      flush: true,
    );
    await temporary.rename(_metadata.path);
  }
}

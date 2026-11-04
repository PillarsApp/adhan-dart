import 'dart:io';
import 'dart:typed_data';

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> readGzipInput(File file) {
  final bytes = file.readAsBytesSync();
  if (bytes.isEmpty) throw const FormatException('empty');
  if (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) {
    throw const FormatException('not gzip');
  }
  final List<int> decoded;
  try {
    decoded = GZipCodec().decode(bytes);
  } on FormatException {
    throw const FormatException('truncated');
  }
  if (bytes.length < 18) throw const FormatException('truncated');
  final trailer = ByteData.sublistView(bytes, bytes.length - 8);
  final crc = trailer.getUint32(0, Endian.little);
  final size = trailer.getUint32(4, Endian.little);
  if (size != decoded.length & 0xFFFFFFFF || crc != _crc32(decoded)) {
    throw const FormatException('truncated');
  }
  return decoded;
}

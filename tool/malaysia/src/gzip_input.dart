import 'dart:io';
import 'dart:typed_data';

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
  final size =
      ByteData.sublistView(bytes, bytes.length - 4).getUint32(0, Endian.little);
  if (size != decoded.length & 0xFFFFFFFF) {
    throw const FormatException('truncated');
  }
  return decoded;
}

// GENERATED — do not edit. Run: dart run tool/embed_hf_token.dart
// obfuscates secret.txt (read-only HF token). Not cryptographic security.

String hfReadToken() {
  const key = <int>[17, 208, 76, 14, 133, 70, 56, 166, 56, 61, 59, 149, 162, 90, 216, 164, 100, 76, 200, 66, 121, 148, 34, 62, 181, 104, 99, 32, 74, 127, 19, 189, 157, 147, 216, 245, 151];
  const enc = <int>[121, 182, 19, 98, 238, 52, 72, 202, 73, 83, 95, 247, 200, 43, 183, 244, 29, 52, 171, 32, 8, 225, 117, 104, 250, 63, 2, 122, 13, 61, 106, 216, 200, 254, 143, 160, 250];
  final out = StringBuffer();
  for (var i = 0; i < enc.length; i++) {
    out.writeCharCode(enc[i] ^ key[i]);
  }
  return out.toString();
}

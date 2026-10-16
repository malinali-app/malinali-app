/// Approximate Wolof orthography as Spanish-readable phonetics.
///
/// Spanish is used because its 'j' (/x/) matches Wolof 'x', and its
/// vowels 'u' and 'ñ' are native matches.
String wolofToSpanishPhonetics(String text) {
  var out = text
      .replaceAll('x', 'j') // Wolof 'x' -> Spanish 'j' (/x/) - the core fix
      .replaceAll('X', 'J')
      .replaceAll('ë', 'e') // Spanish has no schwa, 'e' is the closest pragmatic fit
      .replaceAll('Ë', 'E')
      .replaceAll('c', 'ch') // Wolof 'c' (/c/) -> Spanish 'ch' (/tʃ/)
      .replaceAll('C', 'CH')
      .replaceAll('j', 'y') // Wolof 'j' (/ɟ/) -> Spanish 'y' (/ʝ/)
      .replaceAll('J', 'Y')
      // Wolof 'ŋ' (velar nasal). User notes 'n' is almost silent.
      // Pragmatically mapping to 'g' to avoid 'n' + 'g' sequence.
      .replaceAll('ŋ', 'g') 
      .replaceAll('Ŋ', 'G')
      .replaceAll('ñ', 'ñ') // Native match
      .replaceAll('Ñ', 'Ñ')
      .replaceAll('u', 'u'); // Native match

  // Handle pre-nasalized consonants pragmatically.
  // The user notes 'n' is almost silent in some cases.
  // For 'ng', we keep it as 'ng' because Spanish engines often 
  // pronounce it as a single velar nasal when followed by a vowel.
  
  return out;
}

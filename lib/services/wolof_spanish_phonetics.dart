/// Approximate Wolof orthography as Spanish-readable phonetics.
///
/// Spanish is used because its 'j' (/x/) matches Wolof 'x', and its
/// vowels 'u' and 'ñ' are native matches.
///
/// Replacements apply to the *original* letters only: order matters so that
/// e.g. Wolof `x` → Spanish `j` is not then rewritten by `j` → `di`, and
/// `ŋ` → `g` does not create a fake `gg` digraph.
String wolofToSpanishPhonetics(String text) {
  return text
      // Original Wolof `j` before `x` → `j`, so x-derived j stays Spanish /x/.
      .replaceAll('j', 'di')
      .replaceAll('J', 'Di')
      .replaceAll('ë', 'eu')
      .replaceAll('Ë', 'Eu')
      // Digraph only; then `ŋ` → `g` so a lone g is never invented into `gg`.
      .replaceAll('gg', 'gu')
      .replaceAll('GG', 'GU')
      .replaceAll('Gg', 'Gu')
      .replaceAll('x', 'j') // Wolof 'x' -> Spanish 'j' (/x/) - the core fix
      .replaceAll('X', 'J')
      .replaceAll('c', 'ch') // Wolof 'c' (/c/) -> Spanish 'ch' (/tʃ/)
      .replaceAll('C', 'CH')
      // Wolof 'ŋ' (velar nasal). Pragmatically mapping to 'g'.
      .replaceAll('ŋ', 'g')
      .replaceAll('Ŋ', 'G');
}

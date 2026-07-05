import 'package:flutter/widgets.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:world_countries/world_countries.dart';

// TheTVDB uses ISO 639-2 (3-letter) language codes, but CLDR (via
// flutter_localized_locales) is keyed by 2-letter — map the common ones. Names
// then come back localized in the user's UI language for free.
const _iso639 = {
  'eng': 'en', 'jpn': 'ja', 'fra': 'fr', 'deu': 'de', 'spa': 'es', 'ita': 'it', 'por': 'pt', 'kor': 'ko',
  'zho': 'zh', 'zhtw': 'zh', 'rus': 'ru', 'ara': 'ar', 'hin': 'hi', 'nld': 'nl', 'swe': 'sv', 'nor': 'no',
  'dan': 'da', 'fin': 'fi', 'pol': 'pl', 'tur': 'tr', 'tha': 'th', 'vie': 'vi', 'heb': 'he', 'hun': 'hu',
  'ces': 'cs', 'ell': 'el', 'ukr': 'uk', 'ron': 'ro', 'ind': 'id', 'fas': 'fa', 'cat': 'ca', 'tgl': 'tl',
  'msa': 'ms',
};

/// Localized display name for a TheTVDB language code (3-letter, or 2-letter),
/// falling back to the upper-cased code when unknown.
String langName(BuildContext context, String code) {
  final two = _iso639[code] ?? (code.length == 2 ? code : null);
  final name = two == null ? null : LocaleNames.of(context)?.nameOf(two);
  return name ?? code.toUpperCase();
}

/// Localized country name for a TheTVDB ISO 3166 alpha-3 code (lowercase, e.g.
/// "usa", "jpn"), falling back to the English common name, then the raw code.
String countryName(BuildContext context, String code) {
  final country = WorldCountry.maybeFromCode(code.toUpperCase());
  if (country == null) return code.toUpperCase();
  return context.maybeLocale?.maps.countryTranslations[country] ?? country.name.common;
}

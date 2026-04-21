import 'package:flutter/material.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (!['en', 'si', 'ta'].contains(locale.languageCode)) return;
    _locale = locale;
    notifyListeners();
  }

  void setLocaleFromString(String languageCode) {
    setLocale(Locale(languageCode));
  }
}

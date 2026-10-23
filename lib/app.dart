import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'services/ride_store.dart';
import 'theme.dart';

class MotoLeanApp extends StatelessWidget {
  const MotoLeanApp({super.key, required this.store});

  final RideStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '摩倾 MotoLean',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeScreen(store: store),
    );
  }
}

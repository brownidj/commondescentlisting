import 'package:flutter/material.dart';

import 'features/catalogue/catalogue_shell.dart';

class CommonDescentApp extends StatelessWidget {
  const CommonDescentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Common Descent Listing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246B62)),
      ),
      home: const CatalogueShell(),
    );
  }
}

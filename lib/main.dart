import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:karma_verito/screens/mobile_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verito',
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const AuthMobile(),
      debugShowCheckedModeBanner: false,
    );
  }
}
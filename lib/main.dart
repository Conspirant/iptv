import 'package:flutter/material.dart';
import 'screens/home.dart';

void main() => runApp(M3UPlayer());

class M3UPlayer extends StatefulWidget {
  @override
  _M3UPlayerState createState() => _M3UPlayerState();
}

class _M3UPlayerState extends State<M3UPlayer> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Live Tv',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B8CFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF151A24),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0F17),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B0F17),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF151A24),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.live_tv_rounded, color: Color(0xFF8EAEFF)),
            SizedBox(width: 12),
            Text('Live TV'),
          ],
        ),
      ),
      body: const Home(),
    );
  }
}

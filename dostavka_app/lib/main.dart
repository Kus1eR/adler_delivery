import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/admin_home_screen.dart';
import 'screens/courier_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.loadSavedUrl();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthService()..loadToken(),
      child: const DostavkaApp(),
    ),
  );
}

class DostavkaApp extends StatelessWidget {
  const DostavkaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Доставка',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isLoggedIn) {
      switch (auth.role) {
        case 'admin':
          return const AdminHomeScreen();
        case 'courier':
          return CourierHomeScreen(courierId: auth.courierId);
        default:
          return const LoginScreen();
      }
    }

    return const LoginScreen();
  }
}

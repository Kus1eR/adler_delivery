import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/foreground_service.dart';
import 'screens/login_screen.dart';
import 'screens/admin_home_screen.dart';
import 'screens/courier_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.loadSavedUrl();
  try {
    await ForegroundServiceManager.initialize();
    print('✅ Foreground service initialized');
  } catch (e) {
    print('❌ Foreground service init error: $e');
  }

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

    print('━━━ AuthGate.build() ━━━');
    print('🔍 isLoggedIn: ${auth.isLoggedIn}');
    print('🔍 token: ${auth.token?.substring(0, auth.token != null && auth.token!.length > 10 ? 10 : auth.token?.length ?? 0)}...');
    print('🔍 role: ${auth.role}');
    print('🔍 courierId: ${auth.courierId}');

    if (auth.isLoggedIn) {
      switch (auth.role) {
        case 'admin':
          print('➡️ Routing to AdminHomeScreen');
          return const AdminHomeScreen();
        case 'courier':
          print('➡️ Routing to CourierHomeScreen(courierId: ${auth.courierId})');
          return CourierHomeScreen(courierId: auth.courierId);
        default:
          print('⚠️ Unknown role "${auth.role}", showing LoginScreen');
          return const LoginScreen();
      }
    }

    print('➡️ Not logged in, showing LoginScreen');
    return const LoginScreen();
  }
}
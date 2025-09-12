import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/vision_mate_provider.dart';
import 'screens/home_screen.dart';
import 'config/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style for accessibility
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const VisionMateApp());
}

class VisionMateApp extends StatelessWidget {
  const VisionMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => VisionMateProvider(),
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          brightness: Brightness.dark,
          fontFamily: 'Roboto',
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 18),
            bodyMedium: TextStyle(fontSize: 16),
            titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ),
        home: const VisionMateHomePage(),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(
                1.2,
              ), // Larger text for accessibility
            ),
            child: child!,
          );
        },
      ),
    );
  }
}

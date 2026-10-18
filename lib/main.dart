import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart' show pdfrxFlutterInitialize;

import 'services/share_receiver.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final state = AppState();
  runApp(PaperdriveApp(state: state));
  await state.init();
  // "Condividi" / "Apri con" da altre app: archiviazione automatica.
  ShareReceiver(state.importShared).start();
}

class PaperdriveApp extends StatelessWidget {
  const PaperdriveApp({super.key, required this.state});

  final AppState state;

  static const Color seed = Color(0xFF17541F);

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Paperdrive',
        debugShowCheckedModeBanner: false,
        locale: const Locale('it'),
        supportedLocales: const [Locale('it'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

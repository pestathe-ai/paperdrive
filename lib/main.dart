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

  // Colori Dom Studio (stile Domus).
  static const Color bluCasa = Color(0xFF1D3A8A);
  static const Color bluCasaChiaro = Color(0xFF8FA9F2);
  static const Color aranciTetto = Color(0xFFF28C38);
  static const Color carta = Color(0xFFFFF8F0);
  static const Color bluNotte = Color(0xFF121621);

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'D. Paper Lab',
        debugShowCheckedModeBanner: false,
        locale: const Locale('it'),
        supportedLocales: const [Locale('it'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: bluCasa,
            primary: bluCasa,
            tertiary: aranciTetto,
            surface: carta,
          ),
          scaffoldBackgroundColor: carta,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: bluCasa,
            brightness: Brightness.dark,
            primary: bluCasaChiaro,
            tertiary: aranciTetto,
            surface: bluNotte,
          ),
          scaffoldBackgroundColor: bluNotte,
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

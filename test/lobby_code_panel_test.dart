import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/lobby_code_panel.dart';

Widget _host(Widget child) => MaterialApp(
      theme: hextechTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  // The real platform channel never replies in the widget-test harness, so
  // Clipboard.setData's future would hang forever; answer it like the OS would.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.setData' ? null : null,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('shows the lobby code and a QR action', (tester) async {
    await tester.pumpWidget(_host(const LobbyCodePanel(lobbyId: 'ABCDE')));

    expect(find.text('ABCDE'), findsOneWidget);
    expect(find.text('QR CODE'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('the QR action opens a modal with a scannable code, the lobby code and the link', (tester) async {
    await tester.pumpWidget(_host(const LobbyCodePanel(lobbyId: 'ABCDE')));

    await tester.tap(find.text('QR CODE'));
    await tester.pumpAndSettle();

    // The QR modal renders the code, plus a copyable link that carries it.
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ABCDE'), findsNWidgets(2));
    expect(find.textContaining('lobby=ABCDE'), findsOneWidget);

    // Tapping the link's copy action (the modal's icon button, not the
    // panel's "Copy" button underneath) confirms itself with a check icon.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.copy));
    await tester.pumpAndSettle();
    expect(find.widgetWithIcon(IconButton, Icons.check), findsOneWidget);

    // Let the confirmation timer finish so it does not outlive the test.
    await tester.pump(const Duration(milliseconds: 1600));
  });

  testWidgets('stays usable at a narrow (320px) width', (tester) async {
    final view = tester.view;
    addTearDown(view.reset);
    view.physicalSize = const Size(320, 640);
    view.devicePixelRatio = 1.0;

    await tester.pumpWidget(_host(const LobbyCodePanel(lobbyId: 'ABCDE')));
    await tester.tap(find.text('QR CODE'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

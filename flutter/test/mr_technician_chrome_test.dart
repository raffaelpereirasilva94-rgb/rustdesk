import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/mr_technician_chrome.dart';

void main() {
  test('maps native server state and stopped service', () {
    expect(mrDeskServerState(1, stopped: false), MrDeskServerState.ready);
    expect(mrDeskServerState(0, stopped: false), MrDeskServerState.connecting);
    expect(mrDeskServerState(-1, stopped: false), MrDeskServerState.disconnected);
    expect(mrDeskServerState(null, stopped: false), MrDeskServerState.unavailable);
    expect(mrDeskServerState(99, stopped: false), MrDeskServerState.unavailable);
    expect(mrDeskServerState(1, stopped: true), MrDeskServerState.disconnected);
  });
  test('card widths stay bounded and consistent', () {
    for (final w in [160.0, 320.0, 600.0, 1020.0, 1630.0]) {
      final width = mrDeskCardWidth(w);
      expect(width, greaterThan(0));
      expect(width, lessThanOrEqualTo(w));
      expect(width, lessThanOrEqualTo(320));
    }
    expect(mrDeskCardWidth(0), 0);
  });
  testWidgets('new session prompts for an ID and only submits real destinations',
      (tester) async {
    final requested = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      MrDeskNewSessionButton(enabled: true,
        onConnect: (id) async { requested.add(id); }),
    )));
    final button = find.byTooltip('Nova sessão');
    final connect = find.widgetWithText(ElevatedButton, 'Conectar');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<ElevatedButton>(connect).onPressed, isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(requested, isEmpty);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.enterText(find.byType(TextField), '123456789');
    await tester.pumpAndSettle();
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(requested, ['123456789']);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.enterText(find.byType(TextField), '987654321');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(requested, ['123456789', '987654321']);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('new session is disabled when outgoing connections are restricted',
      (tester) async {
    var requested = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      MrDeskNewSessionButton(enabled: false,
        onConnect: (_) async { requested = true; }),
    )));
    final button = find.byType(IconButton);
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(requested, isFalse);
  });
  test('session list identity includes native window and peer', () {
    const first = [MrDeskSession(1, '123')];
    expect(mrDeskSameSessions(first, const [MrDeskSession(1, '123')]), isTrue);
    expect(mrDeskSameSessions(first, const [MrDeskSession(2, '123')]), isFalse);
    expect(mrDeskSameSessions(first, const []), isFalse);
  });
  testWidgets('wordmark matches approved typography and colors', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: MrDeskWordmark())));
    final text = tester.widget<Text>(find.descendant(
      of: find.byType(MrDeskWordmark), matching: find.byType(Text)));
    final span = text.textSpan as TextSpan;
    expect(span.toPlainText(), 'MRDesk');
    expect(text.style!.fontSize, 16);
    expect(text.style!.fontFamily, 'Inter');
    expect(text.style!.fontWeight, FontWeight.w500);
    expect(text.style!.letterSpacing, -0.3);
    expect((span.children![0] as TextSpan).style!.color, const Color(0xFF5B7FE5));
    expect((span.children![1] as TextSpan).style!.color, const Color(0xFFFCFCFC));
  });
  testWidgets('wordmark and technician palette follow light and dark themes', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light, Brightness.dark]) {
      final dark = brightness == Brightness.dark;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: const Scaffold(body: MrDeskWordmark()),
      ));
      // MaterialApp animates theme changes. Assert only after the transition.
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.byType(MrDeskWordmark))).brightness,
          brightness);
      final text = tester.widget<Text>(find.descendant(
        of: find.byType(MrDeskWordmark), matching: find.byType(Text)));
      final span = text.textSpan as TextSpan;
      expect((span.children![1] as TextSpan).style!.color,
          dark ? const Color(0xFFFCFCFC) : const Color(0xFF172033));
      final palette = MrDeskTechnicianPalette(dark);
      expect(palette.background, dark ? const Color(0xFF0E1421) : const Color(0xFFF6F8FC));
      expect(palette.foreground, dark ? const Color(0xFFF8FAFC) : const Color(0xFF172033));
    }
  });
  testWidgets('device ID is centered, highlighted and copy remains available', (tester) async {
    var copied = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MrDeskLocalId(
      id: '128 118 149', onInfo: () {}, onCopy: () => copied = true,
    ))));
    final id = find.text('128 118 149');
    expect(find.text('Seu Dispositivo'), findsOneWidget);
    expect(find.text('Seu ID de atendimento'), findsNothing);
    final style = tester.widget<Text>(id).style!;
    expect(style.color, const Color(0xFF5B7FE5));
    expect(style.fontSize, 46);
    expect(tester.getCenter(id).dx, closeTo(tester.getCenter(find.byType(MrDeskLocalId)).dx, 1));
    await tester.tap(find.byTooltip('Copiar ID'));
    expect(copied, isTrue);
  });
  testWidgets('only ready status displays a check', (tester) async {
    for (final status in MrDeskServerState.values) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        MrDeskServerIndicator(status: status, publicServer: false))));
      expect(find.byIcon(Icons.check), status == MrDeskServerState.ready ? findsOneWidget : findsNothing);
      expect(find.byType(Tooltip), findsOneWidget);
    }
  });
}

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
  testWidgets('new session requests a separate home window on each click',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      MrDeskNewSessionButton(enabled: true, onOpen: () async { opened++; }),
    )));
    final button = find.byTooltip('Nova sessão');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(opened, 2);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('new session is disabled when outgoing connections are restricted',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      MrDeskNewSessionButton(enabled: false, onOpen: () async { opened = true; }),
    )));
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    expect(opened, isFalse);
  });
  test('independent home launch has no destination and isolates event channels', () {
    expect(mrDeskHomeWindowArguments(), {mrDeskHomeWindowKey: true});
    expect(mrDeskHomeWindowArguments().containsKey('id'), isFalse);
    expect(mrDeskHomeWindowArguments().containsKey('password'), isFalse);
    expect(mrDeskHomeEventChannel(1), isNot(mrDeskHomeEventChannel(2)));
    expect(mrDeskHomeEventChannel(1), isNot('main'));
  });
  test('session list identity includes native window and peer', () {
    const first = [MrDeskSession(1, '123')];
    expect(mrDeskSameSessions(first, const [MrDeskSession(1, '123')]), isTrue);
    expect(mrDeskSameSessions(first, const [MrDeskSession(2, '123')]), isFalse);
    expect(mrDeskSameSessions(first, const []), isFalse);
  });
  test('home session ownership isolates windows and preserves native moves', () {
    final owners = MrDeskSessionOwners();
    final now = DateTime(2026, 11, 27);
    const a = MrDeskSession(11, '111');
    const b = MrDeskSession(12, '222');
    const c = MrDeskSession(12, '333');
    owners.assign('222', 2, now);
    owners.assign('333', 3, now);
    owners.reconcile([a, b, c], now, complete: true);
    expect(owners.forHome([a, b, c], 0), [a]);
    expect(owners.forHome([a, b, c], 2), [b]);
    expect(owners.forHome([a, b, c], 3), [c]);
    expect(owners.forHome([a, b, c], 4), isEmpty);
    const moved = MrDeskSession(19, '222');
    owners.reconcile([a, moved, c], now, complete: true);
    expect(owners.forHome([a, moved, c], 2), [moved]);
    owners.releaseHome(2);
    expect(owners.forHome([a, moved, c], 0), [a, moved]);
    expect(owners.forHome([a, moved, c], 3), [c]);
  });
  test('ownership survives incomplete snapshots and expires after remote close', () {
    final owners = MrDeskSessionOwners();
    final now = DateTime(2026, 11, 27);
    const session = MrDeskSession(10, '123');
    owners.assign('123', 2, now);
    owners.reconcile([], now, complete: true);
    expect(owners.ownerOf('123'), 2);
    owners.reconcile([session], now, complete: true);
    owners.reconcile([], now, complete: false);
    expect(owners.ownerOf('123'), 2);
    owners.reconcile([], now, complete: true);
    expect(owners.ownerOf('123'), 0);
    owners.assign('456', 3, now);
    owners.reconcile([], now.add(const Duration(seconds: 31)), complete: true);
    expect(owners.ownerOf('456'), 0);
  });
  testWidgets('session header scrolls without covering new-window action', (tester) async {
    var opened = 0;
    final sessions = List.generate(8, (i) => MrDeskSession(i + 1, '12345678$i'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 300, height: 36, child: Row(children: [
        MrDeskNewSessionButton(enabled: true, onOpen: () async { opened++; }),
        Expanded(child: MrDeskSessionTabs(sessions: sessions,
          labelFor: (s) => s.peerId, onActivate: (_) {})),
      ])),
    ))));
    expect(tester.takeException(), isNull);
    final button = find.byTooltip('Nova sessão');
    final tabs = find.byType(MrDeskSessionTabs);
    expect(tester.getRect(button).right, lessThanOrEqualTo(tester.getRect(tabs).left));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(button);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
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

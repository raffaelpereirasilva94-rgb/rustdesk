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
  test('session list identity includes native window and peer', () {
    const first = [MrDeskSession(1, '123')];
    expect(mrDeskSameSessions(first, const [MrDeskSession(1, '123')]), isTrue);
    expect(mrDeskSameSessions(first, const [MrDeskSession(2, '123')]), isFalse);
    expect(mrDeskSameSessions(first, const []), isFalse);
  });
  testWidgets('wordmark matches approved typography and colors', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MrDeskWordmark())));
    final text = tester.widget<Text>(find.descendant(
      of: find.byType(MrDeskWordmark), matching: find.byType(Text)));
    final span = text.textSpan as TextSpan;
    expect(span.toPlainText(), 'MRDesk');
    expect(text.style!.fontSize, 16);
    expect(text.style!.fontFamily, 'Segoe UI');
    expect(text.style!.fontWeight, FontWeight.w500);
    expect(text.style!.letterSpacing, -0.3);
    expect((span.children![0] as TextSpan).style!.color, const Color(0xFF5B7FE5));
    expect((span.children![1] as TextSpan).style!.color, const Color(0xFFFCFCFC));
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

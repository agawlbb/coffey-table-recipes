import 'package:coffey_table_recipes/src/email_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login and registration expose grouped credential autofill', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EmailAccess())),
    );
    expect(find.byType(AutofillGroup), findsOneWidget);
    var fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].autofillHints!.first, AutofillHints.username);
    expect(fields[1].autofillHints, [AutofillHints.password]);
    expect(fields[1].keyboardType, TextInputType.visiblePassword);
    expect(fields[1].obscureText, isTrue);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[1].autofillHints!.first, AutofillHints.username);
    expect(fields[2].autofillHints, [AutofillHints.newPassword]);
    expect(fields[3].autofillHints, [AutofillHints.newPassword]);
    for (final index in [2, 3]) {
      expect(fields[index].obscureText, isTrue);
      await tester.showKeyboard(find.byType(TextField).at(index));
      final configuration = tester.testTextInput.setClientArgs!;
      expect(
        configuration['inputType']['name'],
        'TextInputType.visiblePassword',
      );
      expect(configuration['obscureText'], isTrue);
      expect(configuration['autofill']['hints'], ['newPassword']);
      tester.testTextInput.enterText('generated-password-123');
      await tester.pump();
    }
    final form = tester.state<FormState>(find.byType(Form));
    form.validate();
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsNothing);
  });
}

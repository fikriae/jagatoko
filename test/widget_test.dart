import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:jagatoko/main.dart';
import 'package:jagatoko/config/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  });

  testWidgets('Jagatoko app dapat dijalankan', (WidgetTester tester) async {
    await tester.pumpWidget(const JagatokoApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

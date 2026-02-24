import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();   // required by media_kit
  runApp(const MyApp());
}

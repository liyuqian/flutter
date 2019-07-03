import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_gallery/gallery/app.dart' show GalleryApp;
import 'package:flutter/material.dart';

void main() {
  enableFlutterDriverExtension();
  runApp(const GalleryApp(testMode: true));
}

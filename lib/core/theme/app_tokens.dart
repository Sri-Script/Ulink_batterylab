import 'package:flutter/material.dart';

/// Shared visual tokens for U-Link's presentation layer.
abstract final class AppTokens {
  static const background = Color(0xFF0B1218);
  static const surface = Color(0xFF121C26);
  static const elevatedSurface = Color(0xFF17232F);
  static const border = Color(0xFF1F3340);
  static const teal = Color(0xFF2DD4BF);
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFF87171);
  static const text = Color(0xFFE6EDF3);
  static const mutedText = Color(0xFF8CA0B3);

  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s24 = 24.0;

  static const r12 = 12.0;
  static const r16 = 16.0;
  static const r20 = 20.0;

  static const labelStyle = TextStyle(
    color: mutedText,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
}

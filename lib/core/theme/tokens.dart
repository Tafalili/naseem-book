import 'package:material_ui/material_ui.dart';

/// Brand palette: soft, gender-neutral, paper-like.
abstract final class NColors {
  // Neutrals
  static const paper = Color(0xFFFBF7F0); // page background (cream)
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF4EEE4); // cards on paper, inputs
  static const line = Color(0xFFE6DDD0); // borders, dividers
  static const ink = Color(0xFF3B3631); // primary text
  static const inkMuted = Color(0xFF7D746B); // secondary text

  // Brand
  static const sage = Color(0xFF6E9A8B); // primary
  static const sageDark = Color(0xFF4F7A6C);
  static const sageSoft = Color(0xFFDCE9E3);
  static const sand = Color(0xFFE3B595); // secondary (warm)
  static const sandSoft = Color(0xFFF7E6DA);
  static const sky = Color(0xFF9DB7CF); // accent (cool)
  static const skySoft = Color(0xFFE3ECF4);
  static const gold = Color(0xFFBF9A5A); // bookbinding accent, badges

  // Semantic
  static const success = Color(0xFF5E9E6E);
  static const warning = Color(0xFFD9A441);
  static const danger = Color(0xFFC8645A);
  static const info = sky;
}

abstract final class NSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const xxxl = 64.0;
}

abstract final class NRadius {
  static const sm = Radius.circular(8);
  static const md = Radius.circular(14);
  static const lg = Radius.circular(22);
  static const pill = Radius.circular(999);
}

abstract final class NShadow {
  static const soft = [
    BoxShadow(color: Color(0x143B3631), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const lifted = [
    BoxShadow(color: Color(0x1F3B3631), blurRadius: 40, offset: Offset(0, 16)),
  ];
}

abstract final class NBreakpoints {
  static const tablet = 720.0;
  static const desktop = 1100.0;
  static const maxContent = 1200.0;
}

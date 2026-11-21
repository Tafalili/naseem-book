import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';

/// Stylised hardcover used until real product photos are uploaded.
/// Uses the real trim ratio (185.5 × 274.5 mm).
class BookMock extends StatelessWidget {
  const BookMock({
    super.key,
    this.name = 'نسيم',
    this.imageUrl,
    this.tilt = true,
    this.color = NColors.sandSoft,
  });

  final String name;
  final String? imageUrl;
  final bool tilt;
  final Color color;

  static const ratio = 185.5 / 274.5;

  @override
  Widget build(BuildContext context) {
    final cover = AspectRatio(
      aspectRatio: ratio,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadiusDirectional.only(
              topEnd: Radius.circular(10),
              bottomEnd: Radius.circular(10),
              topStart: Radius.circular(3),
              bottomStart: Radius.circular(3),
            ),
            boxShadow: NShadow.lifted,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null)
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                  child: Image.network(imageUrl!, fit: BoxFit.cover),
                )
              else ...[
                // inner frame
                Padding(
                  padding: EdgeInsets.all(w * .09),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: NColors.gold.withValues(alpha: .7), width: 1.2),
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: w * .42,
                      height: w * .42,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: NColors.surface,
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.child_care_rounded, size: w * .2, color: NColors.sage),
                    ),
                    SizedBox(height: w * .08),
                    Text(name,
                        style: TextStyle(
                            fontFamily: NFonts.ruqaa,
                            fontSize: w * .17,
                            height: 1.3,
                            color: NColors.sageDark)),
                    Text('كتاب ذكرياتي الأولى',
                        style: TextStyle(
                            fontFamily: NFonts.ui,
                            fontSize: w * .055,
                            color: NColors.inkMuted)),
                  ],
                ),
              ],
              // spine shading (start edge in RTL = right)
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: w * .05,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.centerStart,
                      end: AlignmentDirectional.centerEnd,
                      colors: [Color(0x26000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
    if (!tilt) return cover;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, .0012)
        ..rotateY(-math.pi / 22),
      child: cover,
    );
  }
}

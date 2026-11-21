# كتاب نسيم (Baby Naseem Book)

Personalized baby photo-book store. Flutter Web (Arabic, RTL) + Supabase.

## Stack
- Flutter 3.50 (web), `material_ui`, `flutter_riverpod`, `go_router`, `supabase_flutter`
- Fonts bundled in `assets/fonts` (no runtime Google Fonts)
- Supabase project `baby-naseem-book` (`edarzlqkxgobdffcfnpx`, eu-central-1)

## Layout
```
lib/
  core/config/env.dart        # Supabase URL + publishable key (override with --dart-define)
  core/theme/                 # tokens (colors, spacing, radii), typography, ThemeData
  core/router/app_router.dart
  features/style_guide/       # Phase 0 design-system sample page (/style)
supabase/migrations/          # schema, RLS, storage buckets
web/index.html                # RTL + Open Graph tags
```

## Run
```bash
flutter pub get
flutter run -d chrome
# other environment:
flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

## Manual Supabase setup
- Auth → enable **Anonymous sign-ins** (guest checkout).
- Add the first owner: insert into `public.admins (user_id, role)` values (`<auth user id>`, `'owner'`).

## Roadmap
0 Foundation ✓ · 1 Storefront · 2 Book editor · 3 Preview & cart · 4 Checkout & tracking · 5 Admin · 6 Print export · 7 Automation & launch

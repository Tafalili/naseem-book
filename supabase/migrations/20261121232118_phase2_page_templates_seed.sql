-- Naseem classic page templates (coords in mm, relative to the 186x276 mm page; cover relative to 200x287 mm artwork).
-- Slot geometry seeded from the designer files; refined later in the admin template editor.
insert into public.page_templates (product_id, page_number, title, background_path, photo_slots, text_slots, is_cover)
select p.id, v.page_number, v.title, v.background_path, v.photo_slots, v.text_slots, v.is_cover
  from public.products p,
  (values
  (0, 'الغلاف', 'asset:templates/naseem-classic/cover_blank.webp', '[]'::jsonb, '[{"id": "cover_name", "x": 24.0, "y": 172.2, "w": 152.0, "h": 34.44, "rotation": 0, "kind": "child_name", "lines": 1, "font_size_mm": 26}]'::jsonb, true),
  (1, 'أهلاً بكم في قصتي', 'asset:templates/naseem-classic/p01.webp', '[]'::jsonb, '[{"id": "t1_1", "x": 40.64, "y": 112.61, "w": 55.88, "h": 13.55, "rotation": 0, "kind": "child_name", "lines": 1, "font_size_mm": 9}]'::jsonb, false),
  (2, 'الخبر السعيد', 'asset:templates/naseem-classic/p02.webp', '[]'::jsonb, '[]'::jsonb, false),
  (3, 'مولود جديد', 'asset:templates/naseem-classic/p03.webp', '[{"id": "p3_1", "x": 77.22, "y": 154.77, "w": 77.22, "h": 70.1, "rotation": -2, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (4, 'سأصبح أماً', 'asset:templates/naseem-classic/p04.webp', '[]'::jsonb, '[]'::jsonb, false),
  (5, 'صورة الأم وهي حامل', 'asset:templates/naseem-classic/p05.webp', '[{"id": "p5_1", "x": 34.54, "y": 30.48, "w": 105.66, "h": 110.74, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (6, 'حفلة استقبال المولود', 'asset:templates/naseem-classic/p06.webp', '[]'::jsonb, '[]'::jsonb, false),
  (7, 'معرفة جنس المولود', 'asset:templates/naseem-classic/p07.webp', '[{"id": "p7_1", "x": 24.72, "y": 47.07, "w": 141.56, "h": 113.45, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (8, 'أهلاً بالمولود', 'asset:templates/naseem-classic/p08.webp', '[]'::jsonb, '[]'::jsonb, false),
  (9, 'أول صورة في المستشفى', 'asset:templates/naseem-classic/p09.webp', '[{"id": "p9_1", "x": 36.91, "y": 75.18, "w": 112.44, "h": 74.17, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (10, 'حكايتي مع اسمي', 'asset:templates/naseem-classic/p10.webp', '[]'::jsonb, '[]'::jsonb, false),
  (11, 'اسمي', 'asset:templates/naseem-classic/p11.webp', '[{"id": "p11_1", "x": 22.01, "y": 16.59, "w": 145.63, "h": 86.02, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (12, 'أول صورة مع الأب', 'asset:templates/naseem-classic/p12.webp', '[{"id": "p12_1", "x": 23.37, "y": 92.79, "w": 136.82, "h": 87.71, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[{"id": "t12_1", "x": 12.7, "y": 193.89, "w": 165.1, "h": 67.73, "rotation": 0, "kind": "memory", "lines": 4, "font_size_mm": 5}]'::jsonb, false),
  (13, 'أول صورة مع الأم', 'asset:templates/naseem-classic/p13.webp', '[{"id": "p13_1", "x": 23.37, "y": 59.61, "w": 135.13, "h": 87.71, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[{"id": "t13_1", "x": 5.08, "y": 185.42, "w": 149.01, "h": 76.2, "rotation": 0, "kind": "memory", "lines": 4, "font_size_mm": 5}]'::jsonb, false),
  (14, 'في المنزل', 'asset:templates/naseem-classic/p14.webp', '[{"id": "p14_1", "x": 15.92, "y": 105.33, "w": 153.08, "h": 81.96, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (15, 'صور مع العائلة', 'asset:templates/naseem-classic/p15.webp', '[{"id": "p15_1", "x": 97.54, "y": 43.69, "w": 59.27, "h": 73.15, "rotation": 0, "shape": "rect", "radius": 0.0}, {"id": "p15_2", "x": 30.82, "y": 82.63, "w": 58.93, "h": 72.81, "rotation": 0, "shape": "rect", "radius": 0.0}, {"id": "p15_3", "x": 97.54, "y": 121.58, "w": 59.27, "h": 73.15, "rotation": 0, "shape": "rect", "radius": 0.0}, {"id": "p15_4", "x": 30.82, "y": 160.53, "w": 58.93, "h": 73.15, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (16, 'الشهر الأول', 'asset:templates/naseem-classic/p16.webp', '[{"id": "p16_1", "x": 56.56, "y": 55.88, "w": 81.28, "h": 79.25, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (17, 'الشهر الثاني', 'asset:templates/naseem-classic/p17.webp', '[{"id": "p17_1", "x": 41.49, "y": 71.97, "w": 103.04, "h": 100.16, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (18, 'الشهر الثالث', 'asset:templates/naseem-classic/p18.webp', '[{"id": "p18_1", "x": 12.53, "y": 172.04, "w": 131.06, "h": 93.81, "rotation": 0, "shape": "rounded", "radius": 3.39}]'::jsonb, '[]'::jsonb, false),
  (19, 'الشهر الرابع', 'asset:templates/naseem-classic/p19.webp', '[{"id": "p19_1", "x": 26.25, "y": 115.15, "w": 131.23, "h": 95.17, "rotation": 0, "shape": "rounded", "radius": 13.55}]'::jsonb, '[]'::jsonb, false),
  (20, 'الشهر الخامس', 'asset:templates/naseem-classic/p20.webp', '[{"id": "p20_1", "x": 13.21, "y": 101.26, "w": 158.83, "h": 87.71, "rotation": 0, "shape": "rounded", "radius": 5.08}]'::jsonb, '[]'::jsonb, false),
  (21, 'الشهر السادس', 'asset:templates/naseem-classic/p21.webp', '[{"id": "p21_1", "x": 27.43, "y": 98.89, "w": 129.71, "h": 78.23, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (22, 'الشهر السابع', 'asset:templates/naseem-classic/p22.webp', '[{"id": "p22_1", "x": 22.01, "y": 88.39, "w": 147.32, "h": 86.7, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (23, 'الشهر الثامن', 'asset:templates/naseem-classic/p23.webp', '[{"id": "p23_1", "x": 12.53, "y": 59.61, "w": 161.21, "h": 110.74, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (24, 'الشهر التاسع', 'asset:templates/naseem-classic/p24.webp', '[{"id": "p24_1", "x": 20.91, "y": 105.83, "w": 146.73, "h": 87.46, "rotation": 0, "shape": "rounded", "radius": 7.62}]'::jsonb, '[]'::jsonb, false),
  (25, 'الشهر العاشر', 'asset:templates/naseem-classic/p25.webp', '[{"id": "p25_1", "x": 21.17, "y": 105.83, "w": 148.17, "h": 88.31, "rotation": 0, "shape": "rounded", "radius": 7.62}]'::jsonb, '[]'::jsonb, false),
  (26, 'الشهر الحادي عشر', 'asset:templates/naseem-classic/p26.webp', '[{"id": "p26_1", "x": 18.63, "y": 78.57, "w": 146.98, "h": 86.7, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (27, 'الشهر الثاني عشر', 'asset:templates/naseem-classic/p27.webp', '[{"id": "p27_1", "x": 19.3, "y": 94.83, "w": 146.98, "h": 86.36, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (28, 'عيد الميلاد', 'asset:templates/naseem-classic/p28.webp', '[]'::jsonb, '[]'::jsonb, false),
  (29, 'صور عيد الميلاد', 'asset:templates/naseem-classic/p29.webp', '[{"id": "p29_1", "x": 18.63, "y": 34.88, "w": 62.65, "h": 88.9, "rotation": 6.5, "shape": "rect", "radius": 0.0}, {"id": "p29_2", "x": 99.74, "y": 49.95, "w": 63.5, "h": 89.75, "rotation": -6.5, "shape": "rect", "radius": 0.0}, {"id": "p29_3", "x": 19.9, "y": 139.53, "w": 62.65, "h": 87.21, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[{"id": "t29_1", "x": 97.37, "y": 176.11, "w": 76.2, "h": 69.43, "rotation": -2, "kind": "memory", "lines": 5, "font_size_mm": 4.5}]'::jsonb, false),
  (30, 'طبعة يدي وقدمي', 'asset:templates/naseem-classic/p30.webp', '[]'::jsonb, '[]'::jsonb, false),
  (31, 'صورتي وأنا نائم', 'asset:templates/naseem-classic/p31.webp', '[{"id": "p31_1", "x": 19.98, "y": 55.2, "w": 151.72, "h": 88.05, "rotation": 0, "shape": "rounded", "radius": 3.39}]'::jsonb, '[]'::jsonb, false),
  (32, 'أول سن وأول خطوة', 'asset:templates/naseem-classic/p32.webp', '[{"id": "p32_1", "x": 92.79, "y": 11.51, "w": 84.33, "h": 156.13, "rotation": 0, "shape": "rect", "radius": 0.0}, {"id": "p32_2", "x": 5.42, "y": 112.1, "w": 83.99, "h": 155.79, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false),
  (33, 'مع إخوتي وأول قصة شعر', 'asset:templates/naseem-classic/p33.webp', '[{"id": "p33_1", "x": 18.37, "y": 14.65, "w": 149.61, "h": 87.46, "rotation": 0, "shape": "rounded", "radius": 9.31}, {"id": "p33_2", "x": 22.01, "y": 146.73, "w": 147.91, "h": 88.05, "rotation": 0, "shape": "rounded", "radius": 9.31}]'::jsonb, '[]'::jsonb, false),
  (34, 'صورة مع العائلة', 'asset:templates/naseem-classic/p34.webp', '[{"id": "p34_1", "x": 36.91, "y": 57.23, "w": 113.79, "h": 83.31, "rotation": 0, "shape": "rect", "radius": 0.0}]'::jsonb, '[]'::jsonb, false)
  ) as v(page_number, title, background_path, photo_slots, text_slots, is_cover)
 where p.slug = 'naseem-classic'
on conflict (product_id, page_number) do update
  set title = excluded.title, background_path = excluded.background_path,
      photo_slots = excluded.photo_slots, text_slots = excluded.text_slots, is_cover = excluded.is_cover;

update public.products set photo_capacity = 33 where slug = 'naseem-classic';

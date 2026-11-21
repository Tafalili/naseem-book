-- User confirmed 2026-11-21: page 186 x 276 mm, no bleed; cover printed on A4 with a 5 mm white stroke.
update public.products
   set specs = (specs - 'design_mm') || '{"trim_mm":{"w":186,"h":276},"bleed_mm":0,"cover_sheet":"A4","cover_white_stroke_mm":5}'::jsonb
 where slug = 'naseem-classic';

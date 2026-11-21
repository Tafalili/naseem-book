-- Real Naseem book designs (bundled web images until admin uploads to the templates bucket).
update public.products
   set cover_image_path = 'asset:catalog/naseem-classic/cover.webp',
       gallery = '["asset:catalog/naseem-classic/spread_1.webp","asset:catalog/naseem-classic/spread_2.webp","asset:catalog/naseem-classic/spread_3.webp","asset:catalog/naseem-classic/spread_4.webp","asset:catalog/naseem-classic/back.webp"]'::jsonb,
       specs = specs || '{"design_mm":{"w":186,"h":276},"print_sheet":"A4","imposition":"odd pages right-aligned, even pages left-aligned, bottom-aligned"}'::jsonb
 where slug = 'naseem-classic';

-- Inside covers (endpaper) and back cover shown in the flip preview.
update public.products
   set specs = specs || jsonb_build_object(
         'endpaper_path',   'asset:templates/naseem-classic/inside_cover.webp',
         'back_cover_path', 'asset:templates/naseem-classic/back_cover.webp')
 where slug = 'naseem-classic';

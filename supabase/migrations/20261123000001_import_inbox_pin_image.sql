-- A imagem do Pin vem dentro da pré-visualização que o atalho manda
-- (até 900 000 caracteres em base64, ver import-product/inspiration_sites.ts).
-- O limite antigo (64 kB) recusava o envio sempre que a imagem vinha.
alter table public.import_inbox drop constraint import_inbox_preview_check;
alter table public.import_inbox add constraint import_inbox_preview_check
  check (octet_length(preview::text) <= 1048576);

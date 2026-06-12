-- SISBRAPAG — receipts storage bucket for manual deposit proofs.
-- Applied to project iiclntwwutsaoorbncfp on 2026-06-12.
-- Path scheme: {user_id}/{deposit_id}.{ext}

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts','receipts', false, 10485760, array['image/png','image/jpeg','image/jpg','application/pdf'])
on conflict (id) do nothing;

create policy "Users upload own receipts" on storage.objects for insert
  with check (bucket_id='receipts' and (auth.uid())::text = (storage.foldername(name))[1]);

create policy "Users read own receipts" on storage.objects for select
  using (bucket_id='receipts' and (auth.uid())::text = (storage.foldername(name))[1]);

create policy "Users delete own receipts" on storage.objects for delete
  using (bucket_id='receipts' and (auth.uid())::text = (storage.foldername(name))[1]);

create policy "Admin reads all receipts" on storage.objects for select
  using (bucket_id='receipts' and (auth.jwt() ->> 'email') = 'jaymepereiranunes@yahoo.com.br');

-- Phase 3 Item #2: Internal messaging system
-- Run this in Supabase SQL Editor

CREATE TABLE public.messages (
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at   timestamptz DEFAULT now() NOT NULL,
  user_id      uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  is_from_admin boolean DEFAULT false NOT NULL,
  body         text NOT NULL,
  read_at      timestamptz DEFAULT NULL
);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Users can read their own messages
CREATE POLICY "messages_user_select" ON public.messages
  FOR SELECT USING (auth.uid() = user_id);

-- Users can insert their own messages (cannot set is_from_admin = true)
CREATE POLICY "messages_user_insert" ON public.messages
  FOR INSERT WITH CHECK (auth.uid() = user_id AND is_from_admin = false);

-- Users can update read_at on their own messages
CREATE POLICY "messages_user_update" ON public.messages
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Admin has full access to all messages
CREATE POLICY "messages_admin_all" ON public.messages
  FOR ALL USING (auth.jwt()->>'email' = 'jaymepereiranunes@yahoo.com.br');

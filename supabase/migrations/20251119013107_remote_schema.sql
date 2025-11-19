drop policy "workflow_executions_delete_all" on "public"."workflow_executions";

drop policy "workflow_executions_insert_all" on "public"."workflow_executions";

drop policy "workflow_executions_select_all" on "public"."workflow_executions";

drop policy "workflow_executions_update_all" on "public"."workflow_executions";

drop policy "workflows_delete_all" on "public"."workflows";

drop policy "workflows_insert_all" on "public"."workflows";

drop policy "workflows_select_all" on "public"."workflows";

drop policy "workflows_update_all" on "public"."workflows";

alter table "public"."action_items" drop constraint "action_items_action_type_check";

alter table "public"."action_items" drop constraint "action_items_priority_check";

alter table "public"."action_items" drop constraint "action_items_status_check";

alter table "public"."approval_queue" drop constraint "approval_queue_status_check";

alter table "public"."campaign_enrollments" drop constraint "campaign_enrollments_status_check";

alter table "public"."campaign_sequences" drop constraint "campaign_sequences_status_check";

alter table "public"."workflow_executions" drop constraint "workflow_executions_status_check";

drop view if exists "public"."profiles_with_email";

drop index if exists "public"."idx_action_items_status_due";

CREATE INDEX idx_action_items_status_due ON public.action_items USING btree (status, due_date) WHERE ((status)::text = ANY ((ARRAY['open'::character varying, 'in_progress'::character varying])::text[]));

alter table "public"."action_items" add constraint "action_items_action_type_check" CHECK (((action_type)::text = ANY ((ARRAY['follow_up'::character varying, 'call'::character varying, 'meeting'::character varying, 'review'::character varying, 'other'::character varying])::text[]))) not valid;

alter table "public"."action_items" validate constraint "action_items_action_type_check";

alter table "public"."action_items" add constraint "action_items_priority_check" CHECK (((priority)::text = ANY ((ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying, 'urgent'::character varying])::text[]))) not valid;

alter table "public"."action_items" validate constraint "action_items_priority_check";

alter table "public"."action_items" add constraint "action_items_status_check" CHECK (((status)::text = ANY ((ARRAY['open'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."action_items" validate constraint "action_items_status_check";

alter table "public"."approval_queue" add constraint "approval_queue_status_check" CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'modified'::character varying])::text[]))) not valid;

alter table "public"."approval_queue" validate constraint "approval_queue_status_check";

alter table "public"."campaign_enrollments" add constraint "campaign_enrollments_status_check" CHECK (((status)::text = ANY ((ARRAY['enrolled'::character varying, 'active'::character varying, 'completed'::character varying, 'unsubscribed'::character varying, 'bounced'::character varying, 'paused'::character varying])::text[]))) not valid;

alter table "public"."campaign_enrollments" validate constraint "campaign_enrollments_status_check";

alter table "public"."campaign_sequences" add constraint "campaign_sequences_status_check" CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'scheduled'::character varying, 'running'::character varying, 'completed'::character varying, 'paused'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."campaign_sequences" validate constraint "campaign_sequences_status_check";

alter table "public"."workflow_executions" add constraint "workflow_executions_status_check" CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'extracting'::character varying, 'executing'::character varying, 'awaiting_approval'::character varying, 'completed'::character varying, 'failed'::character varying])::text[]))) not valid;

alter table "public"."workflow_executions" validate constraint "workflow_executions_status_check";

create or replace view "public"."profiles_with_email" as  SELECT p.profile_id,
    p.auth_user_id,
    p.full_name,
    p.role,
    p.created_at,
    p.updated_at,
    u.email
   FROM (public.profiles p
     JOIN auth.users u ON ((u.id = p.auth_user_id)));



  create policy "Allow insert workflows"
  on "public"."workflows"
  as permissive
  for insert
  to public
with check (true);



  create policy "Allow read workflows"
  on "public"."workflows"
  as permissive
  for select
  to public
using (true);




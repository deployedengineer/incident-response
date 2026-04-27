-- ============================================================
-- INCIDENT RESPONSE RAG – PRODUCTION (VECTOR ONLY – GEMINI 3072)
-- ============================================================
--
-- Design Principles:
-- • Gemini embeddings (3072 dims)
-- • Sequential scan (ANN not used due to dimension limits)
-- • Structured concatenation before embedding
-- • Over-fetch retrieval pattern
-- • Metadata filtering only for resolved incidents
-- • Reference playbooks have NO metadata (simplified)
-- • Embedding version tracking
-- • Soft delete support
-- • Metadata discovery layer
-- • Grouped metadata view
-- • updated_at auto tracking
--
-- ============================================================


-- ============================================================
-- 1️⃣ EXTENSIONS
-- ============================================================

create extension if not exists vector;
create extension if not exists pgcrypto;


-- ============================================================
-- 2️⃣ RESOLVED INCIDENTS (RAG MEMORY)
-- ============================================================
-- Stores historical resolved incidents used for semantic retrieval.
-- Metadata is supported for structured filtering.

create table if not exists resolved_incidents_v1 (
  id uuid primary key default gen_random_uuid(),

  -- Structured concatenated text used for embedding
  content text not null,

  -- Flexible structured metadata (severity, systems, mitre, etc.)
  metadata jsonb not null default '{}'::jsonb,

  -- Explicit columns removed; all contextual data is managed via the metadata JSONB payload

  -- Gemini embedding vector
  embedding vector(3072) not null,

  -- Embedding traceability
  embedding_model text not null default 'gemini-embedding-001',
  embedding_version integer not null default 1,

  -- Soft delete (safer than physical deletion)
  is_active boolean not null default true,

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Index for metadata filtering
create index if not exists resolved_incidents_metadata_idx_v1
on resolved_incidents_v1
using gin (metadata jsonb_path_ops);


-- ============================================================
-- 3️⃣ REFERENCE PLAYBOOKS (VECTOR STORE COMPATIBLE)
-- ============================================================
-- Design aligned with n8n Supabase Vector Insert node.
-- • content → summary used for embedding
-- • embedding → Gemini 3072 vector
-- • metadata → stores name + full_text + any future fields
-- • No NOT NULL constraints on custom fields outside metadata
-- • Fully compatible with vector insertion flow

create table if not exists reference_playbooks_v1 (
  id uuid primary key default gen_random_uuid(),

  -- Summary used for embedding & similarity matching
  content text not null,

  -- Flexible storage for playbook data
  -- Example:
  -- {
  --   "name": "playbook-brute-force-login.md",
  --   "full_text": "# Incident Response Playbook ...",
  --   "type": "identity"
  -- }
  metadata jsonb not null default '{}'::jsonb,

  -- Gemini embedding vector
  embedding vector(3072) not null,

  embedding_model text not null default 'gemini-embedding-001',
  embedding_version integer not null default 1,

  is_active boolean not null default true,

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Optional index if you ever want to filter by metadata
create index if not exists reference_playbooks_metadata_idx_v1
on reference_playbooks_v1
using gin (metadata jsonb_path_ops);


-- ============================================================
-- 4️⃣ TEST INCIDENTS (EVALUATION LAYER)
-- ============================================================

create table if not exists test_incidents_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id text NOT NULL,
  title text,
  category text,
  type text,
  severity text,
  status text,
  assigned_to text,
  "@timestamp" timestamptz,
  affected_systems jsonb DEFAULT '[]'::jsonb,
  mitre jsonb DEFAULT '{}'::jsonb,
  mitre_tactic_ids jsonb DEFAULT '[]'::jsonb,
  mitre_technique_ids jsonb DEFAULT '[]'::jsonb,
  mitre_prevention_ids jsonb DEFAULT '[]'::jsonb,
  detection_method text,
  tags jsonb DEFAULT '[]'::jsonb,

  -- Alert metadata
  description text,         -- raw alert text
  alert_source text,        -- detection tool (GuardDuty, CrowdStrike, etc.)
  rule_name text,           -- exact rule/finding name
  entities jsonb DEFAULT '{}'::jsonb,  -- { users[], ips[], hosts[], domains[], hashes[] }
  files jsonb DEFAULT '[]'::jsonb,     -- executable/file names extracted by EDR (e.g., ["update_service.exe"])
  signal_type text,                    -- classification of detection signal: anomaly | behavioral | signature | threshold | vulnerability_exposure
  confidence text,                     -- alert confidence level from the detection engine: high | medium | low

  -- Final AI generated output
  output jsonb,
  output_markdown text,     -- full Markdown report for human reading
  run_status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);


-- ============================================================
-- 5️⃣ VECTOR SEARCH – RESOLVED INCIDENTS
-- ============================================================
-- Uses:
-- • Over-fetch pattern
-- • Threshold filtering
-- • Soft delete filtering
-- • Defensive metadata filtering

create or replace function match_resolved_incidents_v1 (
  query_embedding vector(3072),
  match_threshold float default 0.0,
  match_count int default 10,
  filter jsonb default '{}'::jsonb
)
returns table (
  id uuid,
  content text,
  metadata jsonb,
  similarity float,
  distance float
)
language sql
stable
as $$
  select *
  from (
    select
      r.id,
      r.content,
      r.metadata,

      1 - (r.embedding <=> query_embedding) as similarity,
      (r.embedding <=> query_embedding) as distance

    from resolved_incidents_v1 r

    where
      r.is_active = true
      and (filter = '{}'::jsonb or r.metadata @> filter)

    order by r.embedding <=> query_embedding
    limit match_count * 4
  ) ranked

  where similarity >= match_threshold

  order by similarity desc
  limit match_count;
$$;


-- ============================================================
-- 🔎 VECTOR SEARCH – REFERENCE PLAYBOOKS (COMPATIBLE)
-- ============================================================
-- Compatible with n8n Supabase Vector Store
-- Required parameter order:
--   1. query_embedding
--   2. match_count
--   3. filter
-- ============================================================

CREATE OR REPLACE FUNCTION match_reference_playbooks_v1 (
  query_embedding vector(3072),
  match_count int DEFAULT 3,
  filter jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  content text,
  metadata jsonb,
  similarity float
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    p.content,

    -- Embed id + name + full_text inside metadata for downstream nodes.
    -- full_text uses p.content (the embedded text IS the full playbook in V1).
    -- This restores V0 behaviour: $json.metadata.full_text is always populated,
    -- so no separate Get row lookup or IF node is required in the workflow.
    jsonb_build_object(
      'id', p.id,
      'name', p.metadata->>'name',
      'full_text', p.content
    ) AS metadata,

    1 - (p.embedding <=> query_embedding) AS similarity

  FROM reference_playbooks_v1 p

  WHERE p.is_active = true

  ORDER BY p.embedding <=> query_embedding

  LIMIT match_count;
$$;


-- ============================================================
-- 7️⃣ METADATA DISCOVERY (RESOLVED INCIDENTS ONLY)
-- ============================================================
-- Allows AI agent / UI to dynamically inspect:
-- • Available metadata keys
-- • Allowed values
-- • Value frequencies

create table if not exists metadata_values_v1 (
  id bigserial primary key,

  field_name text not null,
  field_value text not null,
  value_count integer default 1,

  created_at timestamptz default now(),
  updated_at timestamptz default now(),

  unique(field_name, field_value)
);

create index if not exists metadata_values_field_idx_v1
on metadata_values_v1(field_name);

create index if not exists metadata_values_field_value_idx_v1
on metadata_values_v1(field_name, field_value);


-- ============================================================
-- 8️⃣ METADATA REFRESH FUNCTION
-- ============================================================

create or replace function refresh_metadata_values_v1()
returns void
language plpgsql
as $$
begin

  truncate table metadata_values_v1;

  insert into metadata_values_v1 (field_name, field_value, value_count)
  select
    key,
    value_text,
    count(*)
  from resolved_incidents_v1 r
  cross join lateral jsonb_each(r.metadata) as m(key, value)
  cross join lateral (
      select value #>> '{}' as value_text
      where jsonb_typeof(value) <> 'array'
      union all
      select jsonb_array_elements_text(value)
      where jsonb_typeof(value) = 'array'
  ) v
  where r.is_active = true
    and value_text is not null
    and value_text <> ''
  group by key, value_text;

end;
$$;


-- ============================================================
-- 9️⃣ GROUPED METADATA VIEW
-- ============================================================

create or replace view metadata_values_grouped_v1 as
select json_object_agg(field_name, values) as metadata
from (
  select
    field_name,
    json_agg(distinct field_value order by field_value) as values
  from metadata_values_v1
  group by field_name
) grouped;


-- ============================================================
-- 🔟 AUTO UPDATED_AT TRIGGER
-- ============================================================

create or replace function set_updated_at_v1()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_resolved_updated_v1 on resolved_incidents_v1;
create trigger trg_resolved_updated_v1
before update on resolved_incidents_v1
for each row execute function set_updated_at_v1();

drop trigger if exists trg_playbooks_updated_v1 on reference_playbooks_v1;
create trigger trg_playbooks_updated_v1
before update on reference_playbooks_v1
for each row execute function set_updated_at_v1();

drop trigger if exists trg_test_updated_v1 on test_incidents_v1;
create trigger trg_test_updated_v1
before update on test_incidents_v1
for each row execute function set_updated_at_v1();

-- ============================================================
-- 1️⃣1️⃣ INITIAL METADATA POPULATION
-- ============================================================

select refresh_metadata_values_v1();
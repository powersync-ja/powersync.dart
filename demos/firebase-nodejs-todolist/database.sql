-- Create tables
create table
  public.lists (
    id text not null,
    created_at timestamp with time zone not null default now(),
    name text not null,
    owner_id text not null,
    constraint lists_pkey primary key (id)
  ) tablespace pg_default;

create table
  public.todos (
    id text not null,
    created_at timestamp with time zone null default now(),
    completed_at timestamp with time zone null,
    description text not null,
    completed boolean not null default false,
    created_by text null,
    completed_by text null,
    list_id text not null,
    constraint todos_pkey primary key (id),
    constraint todos_list_id_fkey foreign key (list_id) references lists (id) on delete cascade
  ) tablespace pg_default;

-- Create publication for powersync
create publication powersync for table lists, todos;

-- Set up Row Level Security (RLS)
-- See https://supabase.com/docs/guides/auth/row-level-security for more details.
alter table public.lists
  enable row level security;

alter table public.todos
  enable row level security;

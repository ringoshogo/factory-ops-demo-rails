SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: bump_session_version(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bump_session_version() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$ BEGIN
  NEW.session_version := OLD.session_version + 1;
  RETURN NEW;
END $$;


--
-- Name: current_tenant_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_tenant_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$ SELECT nullif(current_setting('app.tenant_id', true), '')::uuid $$;


--
-- Name: find_login_user(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.find_login_user(login_email text) RETURNS TABLE(id uuid, owner_tenant_id uuid, password_digest character varying, session_version integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$ SELECT u.id, u.owner_tenant_id, u.password_digest, u.session_version FROM public.users u WHERE u.email = login_email $$;


--
-- Name: partnership_active(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.partnership_active(supplier uuid, buyer uuid) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$ SELECT EXISTS (SELECT 1 FROM partnerships p
                  WHERE p.owner_tenant_id = supplier AND p.buyer_tenant_id = buyer AND p.status = 'active') $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: customer_part_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_part_mappings (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    customer_tenant_id uuid NOT NULL,
    customer_part_number character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    item_id uuid NOT NULL
);

ALTER TABLE ONLY public.customer_part_mappings FORCE ROW LEVEL SECURITY;


--
-- Name: items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.items (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    unit character varying NOT NULL,
    unit_price bigint NOT NULL,
    tax_rate_percent integer DEFAULT 10 NOT NULL,
    published boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT items_tax_rate_percent_check CHECK ((tax_rate_percent = ANY (ARRAY[8, 10]))),
    CONSTRAINT items_unit_price_non_negative CHECK ((unit_price >= 0))
);

ALTER TABLE ONLY public.items FORCE ROW LEVEL SECURITY;


--
-- Name: partnership_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partnership_grants (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    permission character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    partnership_id uuid NOT NULL,
    CONSTRAINT partnership_grants_permission_check CHECK (((permission)::text = ANY (ARRAY['view_catalog'::text, 'place_orders'::text, 'view_shipments'::text])))
);

ALTER TABLE ONLY public.partnership_grants FORCE ROW LEVEL SECURITY;


--
-- Name: partnerships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partnerships (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    buyer_tenant_id uuid NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT partnerships_not_self CHECK ((owner_tenant_id <> buyer_tenant_id)),
    CONSTRAINT partnerships_status_revoked_at CHECK (((((status)::text = 'active'::text) AND (revoked_at IS NULL)) OR (((status)::text = 'revoked'::text) AND (revoked_at IS NOT NULL))))
);

ALTER TABLE ONLY public.partnerships FORCE ROW LEVEL SECURITY;


--
-- Name: purchase_order_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_order_lines (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    part_number character varying NOT NULL,
    quantity integer NOT NULL,
    confirmed_item_name character varying,
    confirmed_unit_price bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    purchase_order_id uuid NOT NULL,
    CONSTRAINT purchase_order_lines_confirmed_together CHECK (((confirmed_item_name IS NULL) = (confirmed_unit_price IS NULL))),
    CONSTRAINT purchase_order_lines_quantity_positive CHECK ((quantity > 0))
);

ALTER TABLE ONLY public.purchase_order_lines FORCE ROW LEVEL SECURITY;


--
-- Name: purchase_order_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_order_sequences (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    last_number integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.purchase_order_sequences FORCE ROW LEVEL SECURITY;


--
-- Name: purchase_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_orders (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    order_no character varying NOT NULL,
    supplier_tenant_id uuid NOT NULL,
    order_date date NOT NULL,
    desired_delivery_on date,
    awaiting_match_at timestamp(6) without time zone,
    accepted_at timestamp(6) without time zone,
    cancelled_at timestamp(6) without time zone,
    supplier_cancelled_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT purchase_orders_single_cancellation CHECK (((cancelled_at IS NULL) OR (supplier_cancelled_at IS NULL)))
);

ALTER TABLE ONLY public.purchase_orders FORCE ROW LEVEL SECURITY;


--
-- Name: sales_order_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_order_lines (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    source_purchase_order_line_id uuid NOT NULL,
    customer_part_number character varying NOT NULL,
    item_id uuid,
    item_name character varying,
    unit_price bigint,
    tax_rate_percent integer,
    quantity integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    sales_order_id uuid NOT NULL,
    CONSTRAINT sales_order_lines_matched_together CHECK ((((item_id IS NULL) AND (item_name IS NULL) AND (unit_price IS NULL) AND (tax_rate_percent IS NULL)) OR ((item_id IS NOT NULL) AND (item_name IS NOT NULL) AND (unit_price IS NOT NULL) AND (tax_rate_percent IS NOT NULL)))),
    CONSTRAINT sales_order_lines_quantity_positive CHECK ((quantity > 0))
);

ALTER TABLE ONLY public.sales_order_lines FORCE ROW LEVEL SECURITY;


--
-- Name: sales_order_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_order_sequences (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    last_number integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.sales_order_sequences FORCE ROW LEVEL SECURITY;


--
-- Name: sales_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_orders (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    order_no character varying NOT NULL,
    customer_tenant_id uuid NOT NULL,
    source_purchase_order_id uuid NOT NULL,
    order_date date NOT NULL,
    due_date date,
    confirmed_at timestamp(6) without time zone,
    shipped_at timestamp(6) without time zone,
    inspected_at timestamp(6) without time zone,
    cancelled_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT sales_orders_cancelled_or_shipped CHECK (((cancelled_at IS NULL) OR (shipped_at IS NULL))),
    CONSTRAINT sales_orders_inspected_after_shipped CHECK (((inspected_at IS NULL) OR (shipped_at IS NOT NULL)))
);

ALTER TABLE ONLY public.sales_orders FORCE ROW LEVEL SECURITY;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: solid_queue_batch_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_batch_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_batch_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_batch_executions_id_seq OWNED BY public.solid_queue_batch_executions.id;


--
-- Name: solid_queue_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_batches (
    id bigint NOT NULL,
    active_job_batch_id character varying,
    description character varying,
    on_finish text,
    on_success text,
    on_failure text,
    metadata text,
    total_jobs integer DEFAULT 0 NOT NULL,
    completed_jobs integer DEFAULT 0 NOT NULL,
    failed_jobs integer DEFAULT 0 NOT NULL,
    enqueued_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_batches_id_seq OWNED BY public.solid_queue_batches.id;


--
-- Name: solid_queue_blocked_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_blocked_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    concurrency_key character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_blocked_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_blocked_executions_id_seq OWNED BY public.solid_queue_blocked_executions.id;


--
-- Name: solid_queue_claimed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_claimed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    process_id bigint,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_claimed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_claimed_executions_id_seq OWNED BY public.solid_queue_claimed_executions.id;


--
-- Name: solid_queue_failed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_failed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    error text,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_failed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_failed_executions_id_seq OWNED BY public.solid_queue_failed_executions.id;


--
-- Name: solid_queue_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_jobs (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    class_name character varying NOT NULL,
    arguments text,
    priority integer DEFAULT 0 NOT NULL,
    active_job_id character varying,
    scheduled_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    concurrency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    batch_id bigint
);


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_jobs_id_seq OWNED BY public.solid_queue_jobs.id;


--
-- Name: solid_queue_pauses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_pauses (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_pauses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_pauses_id_seq OWNED BY public.solid_queue_pauses.id;


--
-- Name: solid_queue_processes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_processes (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    last_heartbeat_at timestamp(6) without time zone NOT NULL,
    supervisor_id bigint,
    pid integer NOT NULL,
    hostname character varying,
    metadata text,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL
);


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_processes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_processes_id_seq OWNED BY public.solid_queue_processes.id;


--
-- Name: solid_queue_ready_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_ready_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_ready_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_ready_executions_id_seq OWNED BY public.solid_queue_ready_executions.id;


--
-- Name: solid_queue_recurring_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    task_key character varying NOT NULL,
    run_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_executions_id_seq OWNED BY public.solid_queue_recurring_executions.id;


--
-- Name: solid_queue_recurring_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_tasks (
    id bigint NOT NULL,
    key character varying NOT NULL,
    schedule character varying NOT NULL,
    command character varying(2048),
    class_name character varying,
    arguments text,
    queue_name character varying,
    priority integer DEFAULT 0,
    static boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_tasks_id_seq OWNED BY public.solid_queue_recurring_tasks.id;


--
-- Name: solid_queue_scheduled_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_scheduled_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_scheduled_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_scheduled_executions_id_seq OWNED BY public.solid_queue_scheduled_executions.id;


--
-- Name: solid_queue_semaphores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_semaphores (
    id bigint NOT NULL,
    key character varying NOT NULL,
    value integer DEFAULT 1 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_semaphores_id_seq OWNED BY public.solid_queue_semaphores.id;


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id uuid DEFAULT uuidv7() NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    partner_code character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    email character varying NOT NULL,
    name character varying NOT NULL,
    role character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    password_digest character varying NOT NULL,
    session_version integer DEFAULT 0 NOT NULL,
    CONSTRAINT users_role_check CHECK (((role)::text = ANY (ARRAY['admin'::text, 'member'::text])))
);

ALTER TABLE ONLY public.users FORCE ROW LEVEL SECURITY;


--
-- Name: solid_queue_batch_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_batch_executions_id_seq'::regclass);


--
-- Name: solid_queue_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batches ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_batches_id_seq'::regclass);


--
-- Name: solid_queue_blocked_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_blocked_executions_id_seq'::regclass);


--
-- Name: solid_queue_claimed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_claimed_executions_id_seq'::regclass);


--
-- Name: solid_queue_failed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_failed_executions_id_seq'::regclass);


--
-- Name: solid_queue_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_jobs_id_seq'::regclass);


--
-- Name: solid_queue_pauses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_pauses_id_seq'::regclass);


--
-- Name: solid_queue_processes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_processes_id_seq'::regclass);


--
-- Name: solid_queue_ready_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_ready_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_tasks_id_seq'::regclass);


--
-- Name: solid_queue_scheduled_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_scheduled_executions_id_seq'::regclass);


--
-- Name: solid_queue_semaphores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_semaphores_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: customer_part_mappings customer_part_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_part_mappings
    ADD CONSTRAINT customer_part_mappings_pkey PRIMARY KEY (id);


--
-- Name: items items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (id);


--
-- Name: partnership_grants partnership_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partnership_grants
    ADD CONSTRAINT partnership_grants_pkey PRIMARY KEY (id);


--
-- Name: partnerships partnerships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partnerships
    ADD CONSTRAINT partnerships_pkey PRIMARY KEY (id);


--
-- Name: purchase_order_lines purchase_order_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT purchase_order_lines_pkey PRIMARY KEY (id);


--
-- Name: purchase_order_sequences purchase_order_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_sequences
    ADD CONSTRAINT purchase_order_sequences_pkey PRIMARY KEY (id);


--
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);


--
-- Name: sales_order_lines sales_order_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_lines
    ADD CONSTRAINT sales_order_lines_pkey PRIMARY KEY (id);


--
-- Name: sales_order_sequences sales_order_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_sequences
    ADD CONSTRAINT sales_order_sequences_pkey PRIMARY KEY (id);


--
-- Name: sales_orders sales_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: solid_queue_batch_executions solid_queue_batch_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT solid_queue_batch_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_batches solid_queue_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batches
    ADD CONSTRAINT solid_queue_batches_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_blocked_executions solid_queue_blocked_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT solid_queue_blocked_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_claimed_executions solid_queue_claimed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT solid_queue_claimed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_failed_executions solid_queue_failed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT solid_queue_failed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_jobs solid_queue_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs
    ADD CONSTRAINT solid_queue_jobs_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_pauses solid_queue_pauses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses
    ADD CONSTRAINT solid_queue_pauses_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_processes solid_queue_processes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes
    ADD CONSTRAINT solid_queue_processes_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_ready_executions solid_queue_ready_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT solid_queue_ready_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_executions solid_queue_recurring_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT solid_queue_recurring_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_tasks solid_queue_recurring_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks
    ADD CONSTRAINT solid_queue_recurring_tasks_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_scheduled_executions solid_queue_scheduled_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT solid_queue_scheduled_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_semaphores solid_queue_semaphores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores
    ADD CONSTRAINT solid_queue_semaphores_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_on_owner_tenant_id_purchase_order_id_bb29b0b793; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_owner_tenant_id_purchase_order_id_bb29b0b793 ON public.purchase_order_lines USING btree (owner_tenant_id, purchase_order_id);


--
-- Name: idx_on_purchase_order_id_part_number_bda45e1f84; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_purchase_order_id_part_number_bda45e1f84 ON public.purchase_order_lines USING btree (purchase_order_id, part_number);


--
-- Name: index_customer_part_mappings_on_customer_part; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customer_part_mappings_on_customer_part ON public.customer_part_mappings USING btree (owner_tenant_id, customer_tenant_id, customer_part_number);


--
-- Name: index_customer_part_mappings_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customer_part_mappings_on_owner_tenant_id_and_id ON public.customer_part_mappings USING btree (owner_tenant_id, id);


--
-- Name: index_customer_part_mappings_on_owner_tenant_id_and_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_part_mappings_on_owner_tenant_id_and_item_id ON public.customer_part_mappings USING btree (owner_tenant_id, item_id);


--
-- Name: index_items_on_owner_tenant_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_items_on_owner_tenant_id_and_code ON public.items USING btree (owner_tenant_id, code);


--
-- Name: index_items_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_items_on_owner_tenant_id_and_id ON public.items USING btree (owner_tenant_id, id);


--
-- Name: index_partnership_grants_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_partnership_grants_on_owner_tenant_id_and_id ON public.partnership_grants USING btree (owner_tenant_id, id);


--
-- Name: index_partnership_grants_on_owner_tenant_id_and_partnership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_partnership_grants_on_owner_tenant_id_and_partnership_id ON public.partnership_grants USING btree (owner_tenant_id, partnership_id);


--
-- Name: index_partnership_grants_on_partnership_id_and_permission; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_partnership_grants_on_partnership_id_and_permission ON public.partnership_grants USING btree (partnership_id, permission);


--
-- Name: index_partnerships_active_pair; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_partnerships_active_pair ON public.partnerships USING btree (owner_tenant_id, buyer_tenant_id) WHERE ((status)::text = 'active'::text);


--
-- Name: index_partnerships_on_buyer_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_partnerships_on_buyer_tenant_id ON public.partnerships USING btree (buyer_tenant_id);


--
-- Name: index_partnerships_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_partnerships_on_owner_tenant_id_and_id ON public.partnerships USING btree (owner_tenant_id, id);


--
-- Name: index_purchase_order_lines_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchase_order_lines_on_owner_tenant_id_and_id ON public.purchase_order_lines USING btree (owner_tenant_id, id);


--
-- Name: index_purchase_order_sequences_on_owner_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchase_order_sequences_on_owner_tenant_id ON public.purchase_order_sequences USING btree (owner_tenant_id);


--
-- Name: index_purchase_order_sequences_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchase_order_sequences_on_owner_tenant_id_and_id ON public.purchase_order_sequences USING btree (owner_tenant_id, id);


--
-- Name: index_purchase_orders_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchase_orders_on_owner_tenant_id_and_id ON public.purchase_orders USING btree (owner_tenant_id, id);


--
-- Name: index_purchase_orders_on_owner_tenant_id_and_order_no; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchase_orders_on_owner_tenant_id_and_order_no ON public.purchase_orders USING btree (owner_tenant_id, order_no);


--
-- Name: index_purchase_orders_on_supplier_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchase_orders_on_supplier_tenant_id ON public.purchase_orders USING btree (supplier_tenant_id);


--
-- Name: index_sales_order_lines_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sales_order_lines_on_owner_tenant_id_and_id ON public.sales_order_lines USING btree (owner_tenant_id, id);


--
-- Name: index_sales_order_lines_on_owner_tenant_id_and_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_order_lines_on_owner_tenant_id_and_item_id ON public.sales_order_lines USING btree (owner_tenant_id, item_id);


--
-- Name: index_sales_order_lines_on_owner_tenant_id_and_sales_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_order_lines_on_owner_tenant_id_and_sales_order_id ON public.sales_order_lines USING btree (owner_tenant_id, sales_order_id);


--
-- Name: index_sales_order_lines_on_source_purchase_order_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sales_order_lines_on_source_purchase_order_line_id ON public.sales_order_lines USING btree (source_purchase_order_line_id);


--
-- Name: index_sales_order_sequences_on_owner_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sales_order_sequences_on_owner_tenant_id ON public.sales_order_sequences USING btree (owner_tenant_id);


--
-- Name: index_sales_order_sequences_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sales_order_sequences_on_owner_tenant_id_and_id ON public.sales_order_sequences USING btree (owner_tenant_id, id);


--
-- Name: index_sales_orders_on_customer_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sales_orders_on_customer_tenant_id ON public.sales_orders USING btree (customer_tenant_id);


--
-- Name: index_sales_orders_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sales_orders_on_owner_tenant_id_and_id ON public.sales_orders USING btree (owner_tenant_id, id);


--
-- Name: index_sales_orders_on_owner_tenant_id_and_order_no; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sales_orders_on_owner_tenant_id_and_order_no ON public.sales_orders USING btree (owner_tenant_id, order_no);


--
-- Name: index_sales_orders_on_source_purchase_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sales_orders_on_source_purchase_order_id ON public.sales_orders USING btree (source_purchase_order_id);


--
-- Name: index_solid_queue_batch_executions_on_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_batch_executions_on_batch_id ON public.solid_queue_batch_executions USING btree (batch_id);


--
-- Name: index_solid_queue_batch_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batch_executions_on_job_id ON public.solid_queue_batch_executions USING btree (job_id);


--
-- Name: index_solid_queue_batches_on_active_job_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batches_on_active_job_batch_id ON public.solid_queue_batches USING btree (active_job_batch_id);


--
-- Name: index_solid_queue_batches_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_batches_on_finished_at ON public.solid_queue_batches USING btree (finished_at);


--
-- Name: index_solid_queue_blocked_executions_for_maintenance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_maintenance ON public.solid_queue_blocked_executions USING btree (expires_at, concurrency_key);


--
-- Name: index_solid_queue_blocked_executions_for_release; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_release ON public.solid_queue_blocked_executions USING btree (concurrency_key, priority, job_id);


--
-- Name: index_solid_queue_blocked_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_blocked_executions_on_job_id ON public.solid_queue_blocked_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_claimed_executions_on_job_id ON public.solid_queue_claimed_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_process_id_and_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_claimed_executions_on_process_id_and_job_id ON public.solid_queue_claimed_executions USING btree (process_id, job_id);


--
-- Name: index_solid_queue_dispatch_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_dispatch_all ON public.solid_queue_scheduled_executions USING btree (scheduled_at, priority, job_id);


--
-- Name: index_solid_queue_failed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_failed_executions_on_job_id ON public.solid_queue_failed_executions USING btree (job_id);


--
-- Name: index_solid_queue_jobs_for_alerting; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_alerting ON public.solid_queue_jobs USING btree (scheduled_at, finished_at);


--
-- Name: index_solid_queue_jobs_for_filtering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_filtering ON public.solid_queue_jobs USING btree (queue_name, finished_at);


--
-- Name: index_solid_queue_jobs_on_active_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_active_job_id ON public.solid_queue_jobs USING btree (active_job_id);


--
-- Name: index_solid_queue_jobs_on_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_batch_id ON public.solid_queue_jobs USING btree (batch_id);


--
-- Name: index_solid_queue_jobs_on_class_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_class_name ON public.solid_queue_jobs USING btree (class_name);


--
-- Name: index_solid_queue_jobs_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_finished_at ON public.solid_queue_jobs USING btree (finished_at);


--
-- Name: index_solid_queue_pauses_on_queue_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_pauses_on_queue_name ON public.solid_queue_pauses USING btree (queue_name);


--
-- Name: index_solid_queue_poll_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_all ON public.solid_queue_ready_executions USING btree (priority, job_id);


--
-- Name: index_solid_queue_poll_by_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_by_queue ON public.solid_queue_ready_executions USING btree (queue_name, priority, job_id);


--
-- Name: index_solid_queue_processes_on_last_heartbeat_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_last_heartbeat_at ON public.solid_queue_processes USING btree (last_heartbeat_at);


--
-- Name: index_solid_queue_processes_on_name_and_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_processes_on_name_and_supervisor_id ON public.solid_queue_processes USING btree (name, supervisor_id);


--
-- Name: index_solid_queue_processes_on_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_supervisor_id ON public.solid_queue_processes USING btree (supervisor_id);


--
-- Name: index_solid_queue_ready_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_ready_executions_on_job_id ON public.solid_queue_ready_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_job_id ON public.solid_queue_recurring_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_task_key_and_run_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_task_key_and_run_at ON public.solid_queue_recurring_executions USING btree (task_key, run_at);


--
-- Name: index_solid_queue_recurring_tasks_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_tasks_on_key ON public.solid_queue_recurring_tasks USING btree (key);


--
-- Name: index_solid_queue_recurring_tasks_on_static; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_recurring_tasks_on_static ON public.solid_queue_recurring_tasks USING btree (static);


--
-- Name: index_solid_queue_scheduled_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_scheduled_executions_on_job_id ON public.solid_queue_scheduled_executions USING btree (job_id);


--
-- Name: index_solid_queue_semaphores_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_expires_at ON public.solid_queue_semaphores USING btree (expires_at);


--
-- Name: index_solid_queue_semaphores_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_semaphores_on_key ON public.solid_queue_semaphores USING btree (key);


--
-- Name: index_solid_queue_semaphores_on_key_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_key_and_value ON public.solid_queue_semaphores USING btree (key, value);


--
-- Name: index_tenants_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tenants_on_code ON public.tenants USING btree (code);


--
-- Name: index_tenants_on_partner_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tenants_on_partner_code ON public.tenants USING btree (partner_code);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_owner_tenant_id_and_id ON public.users USING btree (owner_tenant_id, id);


--
-- Name: users users_bump_session_version; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_bump_session_version BEFORE UPDATE OF password_digest ON public.users FOR EACH ROW WHEN (((old.password_digest)::text IS DISTINCT FROM (new.password_digest)::text)) EXECUTE FUNCTION public.bump_session_version();


--
-- Name: sales_order_lines fk_rails_151983be39; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_lines
    ADD CONSTRAINT fk_rails_151983be39 FOREIGN KEY (owner_tenant_id, sales_order_id) REFERENCES public.sales_orders(owner_tenant_id, id);


--
-- Name: items fk_rails_1795f753e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT fk_rails_1795f753e1 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: sales_orders fk_rails_27f737e6dc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT fk_rails_27f737e6dc FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: sales_order_sequences fk_rails_2a441d70a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_sequences
    ADD CONSTRAINT fk_rails_2a441d70a1 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: purchase_orders fk_rails_341ad3ae86; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT fk_rails_341ad3ae86 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: solid_queue_failed_executions fk_rails_39bbc7a631; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT fk_rails_39bbc7a631 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: partnership_grants fk_rails_3faf5a3355; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partnership_grants
    ADD CONSTRAINT fk_rails_3faf5a3355 FOREIGN KEY (owner_tenant_id, partnership_id) REFERENCES public.partnerships(owner_tenant_id, id);


--
-- Name: solid_queue_blocked_executions fk_rails_4cd34e2228; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT fk_rails_4cd34e2228 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: purchase_order_lines fk_rails_4f03626e15; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT fk_rails_4f03626e15 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: customer_part_mappings fk_rails_68fd608b68; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_part_mappings
    ADD CONSTRAINT fk_rails_68fd608b68 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: partnerships fk_rails_6be6936b70; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partnerships
    ADD CONSTRAINT fk_rails_6be6936b70 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: sales_order_lines fk_rails_6ea4e05c77; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_lines
    ADD CONSTRAINT fk_rails_6ea4e05c77 FOREIGN KEY (owner_tenant_id, item_id) REFERENCES public.items(owner_tenant_id, id);


--
-- Name: solid_queue_batch_executions fk_rails_7c5e073422; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_7c5e073422 FOREIGN KEY (batch_id) REFERENCES public.solid_queue_batches(id) ON DELETE CASCADE;


--
-- Name: solid_queue_ready_executions fk_rails_81fcbd66af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT fk_rails_81fcbd66af FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: purchase_order_lines fk_rails_845c3726cf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT fk_rails_845c3726cf FOREIGN KEY (owner_tenant_id, purchase_order_id) REFERENCES public.purchase_orders(owner_tenant_id, id);


--
-- Name: solid_queue_claimed_executions fk_rails_9cfe4d4944; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT fk_rails_9cfe4d4944 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: purchase_order_sequences fk_rails_b667ad88d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_sequences
    ADD CONSTRAINT fk_rails_b667ad88d0 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: solid_queue_batch_executions fk_rails_bc9f981155; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_bc9f981155 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: solid_queue_scheduled_executions fk_rails_c4316f352d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT fk_rails_c4316f352d FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: sales_order_lines fk_rails_cfa1b9b0af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_lines
    ADD CONSTRAINT fk_rails_cfa1b9b0af FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: customer_part_mappings fk_rails_d76de7871e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_part_mappings
    ADD CONSTRAINT fk_rails_d76de7871e FOREIGN KEY (owner_tenant_id, item_id) REFERENCES public.items(owner_tenant_id, id);


--
-- Name: users fk_rails_e665ff9db8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_e665ff9db8 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: partnership_grants fk_rails_e6ea4224b6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partnership_grants
    ADD CONSTRAINT fk_rails_e6ea4224b6 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: customer_part_mappings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_part_mappings ENABLE ROW LEVEL SECURITY;

--
-- Name: items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_part_mappings owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.customer_part_mappings USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: items owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.items USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: partnership_grants owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.partnership_grants USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: partnerships owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.partnerships USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: purchase_order_lines owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.purchase_order_lines USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: purchase_order_sequences owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.purchase_order_sequences USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: purchase_orders owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.purchase_orders USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: sales_order_lines owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.sales_order_lines USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: sales_order_sequences owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.sales_order_sequences USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: sales_orders owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.sales_orders USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: users owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.users USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: items partner_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY partner_read ON public.items FOR SELECT USING ((published AND public.partnership_active(owner_tenant_id, public.current_tenant_id())));


--
-- Name: partnership_grants partner_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY partner_read ON public.partnership_grants FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.partnerships p
  WHERE (p.id = partnership_grants.partnership_id))));


--
-- Name: partnerships partner_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY partner_read ON public.partnerships FOR SELECT USING (((buyer_tenant_id = public.current_tenant_id()) AND ((status)::text = 'active'::text)));


--
-- Name: partnership_grants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.partnership_grants ENABLE ROW LEVEL SECURITY;

--
-- Name: partnerships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.partnerships ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_order_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_order_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_order_sequences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_order_sequences ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_order_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_order_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_order_sequences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_order_sequences ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261008000600'),
('20261008000500'),
('20261008000400'),
('20261008000300'),
('20261008000210'),
('20261008000200'),
('20261008000100'),
('20261008000000'),
('20261007220100'),
('20261007220000'),
('20261007203750');


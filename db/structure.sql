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
-- Name: audit_logs_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_logs_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'audit_logs は書き換えられない';
  ELSIF TG_OP = 'TRUNCATE' THEN
    RAISE EXCEPTION 'audit_logs は TRUNCATE できない';
  ELSIF OLD.occurred_at >= now() - interval '7 years' THEN
    RAISE EXCEPTION '保存期間の中の audit_logs の行は消せない';
  END IF;
  RETURN OLD;
END
$$;


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


--
-- Name: purge_expired_audit_logs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purge_expired_audit_logs() RETURNS bigint
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
  WITH deleted AS (DELETE FROM public.audit_logs WHERE occurred_at < now() - interval '7 years' RETURNING 1)
  SELECT count(*) FROM deleted
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.allocations (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    sales_order_line_id uuid NOT NULL,
    item_id uuid NOT NULL,
    quantity integer NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT allocations_quantity_positive CHECK ((quantity > 0)),
    CONSTRAINT allocations_status_check CHECK (((status)::text = ANY (ARRAY['active'::text, 'released'::text, 'consumed'::text])))
);

ALTER TABLE ONLY public.allocations FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE allocations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.allocations IS '[在庫] 引当。受注明細ごとに 1 行で、引き当てた数量と状態を持つ';


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
-- Name: TABLE ar_internal_metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ar_internal_metadata IS '[基盤] DB の環境名などの記録。Rails が管理する';


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    occurred_at timestamp(6) without time zone DEFAULT now() NOT NULL,
    actor_type character varying NOT NULL,
    actor_user_id uuid,
    action character varying NOT NULL,
    target_type character varying NOT NULL,
    target_id uuid NOT NULL,
    counterparty_tenant_id uuid,
    request_id character varying,
    correlation_id character varying NOT NULL,
    causation_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT audit_logs_actor_type_check CHECK (((actor_type)::text = ANY (ARRAY['user'::text, 'system'::text]))),
    CONSTRAINT audit_logs_actor_user_check CHECK ((((actor_type)::text = 'user'::text) = (actor_user_id IS NOT NULL)))
);

ALTER TABLE ONLY public.audit_logs FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE audit_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.audit_logs IS '[基盤] 監査ログ。相手テナントに効果が及ぶ書き込みを 1 行ずつ追記し、書き換えない';


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
-- Name: TABLE customer_part_mappings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.customer_part_mappings IS '[受注] 得意先品番の対応表。取引先の品番を自社の品目に照合する';


--
-- Name: inbound_shipment_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbound_shipment_lines (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    shipped_quantity integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    inbound_shipment_id uuid NOT NULL,
    purchase_order_line_id uuid NOT NULL,
    CONSTRAINT inbound_shipment_lines_shipped_quantity_positive CHECK ((shipped_quantity > 0))
);

ALTER TABLE ONLY public.inbound_shipment_lines FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE inbound_shipment_lines; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.inbound_shipment_lines IS '[購買] 入荷の明細。発注明細ごとの出荷数量を持つ';


--
-- Name: inbound_shipments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbound_shipments (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    shipment_id uuid NOT NULL,
    shipped_on date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    purchase_order_id uuid NOT NULL
);

ALTER TABLE ONLY public.inbound_shipments FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE inbound_shipments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.inbound_shipments IS '[購買] 入荷。受注側の「出荷計上」の写しで、出荷実績 1 件に 1 行';


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
-- Name: TABLE items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.items IS '[受注] 品目カタログ。公開した品目は、取引関係のある発注側から見える';


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
-- Name: TABLE partnership_grants; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.partnership_grants IS '[取引関係] 取引関係ごとの権限付与（view_catalog・place_orders・view_shipments）';


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
-- Name: TABLE partnerships; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.partnerships IS '[取引関係] 受注側が発注側と結ぶ取引関係。失効した関係も行として残す';


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
-- Name: TABLE purchase_order_lines; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purchase_order_lines IS '[購買] 発注明細。自社品番と数量、受注確定で写す品目名・単価を持つ';


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
-- Name: TABLE purchase_order_sequences; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purchase_order_sequences IS '[購買] 発注の伝票番号の採番行。テナントごとに最後に払い出した番号を持つ';


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
-- Name: TABLE purchase_orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purchase_orders IS '[購買] 発注の見出し。状況は時刻列と入荷・検収から導出する';


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
-- Name: TABLE sales_order_lines; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.sales_order_lines IS '[受注] 受注明細。照合までは品目が空で、照合で品目名・単価・税率を写す';


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
-- Name: TABLE sales_order_sequences; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.sales_order_sequences IS '[受注] 受注の伝票番号の採番行。テナントごとに最後に払い出した番号を持つ';


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
-- Name: TABLE sales_orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.sales_orders IS '[受注] 発注から連結した受注の見出し。状況は時刻列から導出する';


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.schema_migrations IS '[基盤] 流したマイグレーションの版。Rails が管理する';


--
-- Name: shipment_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shipment_lines (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    source_purchase_order_line_id uuid NOT NULL,
    quantity integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    shipment_id uuid NOT NULL,
    shipment_request_line_id uuid NOT NULL,
    CONSTRAINT shipment_lines_quantity_positive CHECK ((quantity > 0))
);

ALTER TABLE ONLY public.shipment_lines FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE shipment_lines; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.shipment_lines IS '[出荷] 出荷実績の明細。出荷依頼の明細ごとに 1 行';


--
-- Name: shipment_request_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shipment_request_lines (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    sales_order_line_id uuid NOT NULL,
    source_purchase_order_line_id uuid NOT NULL,
    item_id uuid NOT NULL,
    quantity integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    shipment_request_id uuid NOT NULL,
    CONSTRAINT shipment_request_lines_quantity_positive CHECK ((quantity > 0))
);

ALTER TABLE ONLY public.shipment_request_lines FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE shipment_request_lines; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.shipment_request_lines IS '[出荷] 出荷依頼の明細。受注明細ごとの品目と数量の写し';


--
-- Name: shipment_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shipment_requests (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    sales_order_id uuid NOT NULL,
    buyer_tenant_id uuid NOT NULL,
    source_purchase_order_id uuid NOT NULL,
    due_date date,
    cancelled_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.shipment_requests FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE shipment_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.shipment_requests IS '[出荷] 出荷依頼。受注の「出荷可能」の写しで、受注ごとに 1 件';


--
-- Name: shipments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shipments (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    buyer_tenant_id uuid NOT NULL,
    source_purchase_order_id uuid NOT NULL,
    shipped_on date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    shipping_instruction_id uuid NOT NULL,
    shipment_request_id uuid NOT NULL
);

ALTER TABLE ONLY public.shipments FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE shipments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.shipments IS '[出荷] 出荷実績。出荷依頼を全量で計上し、発注側は自社の発注に連結した分を読む';


--
-- Name: shipping_instructions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shipping_instructions (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    planned_date date NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    shipment_request_id uuid NOT NULL,
    CONSTRAINT shipping_instructions_status_check CHECK (((status)::text = ANY (ARRAY['active'::text, 'cancelled'::text])))
);

ALTER TABLE ONLY public.shipping_instructions FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE shipping_instructions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.shipping_instructions IS '[出荷] 出荷指示。有効な指示は出荷依頼ごとに 1 件';


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
-- Name: TABLE solid_queue_batch_executions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_batch_executions IS '[キュー] バッチに属するジョブと、そのバッチの対応';


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
-- Name: TABLE solid_queue_batches; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_batches IS '[キュー] ジョブのバッチと、その進み具合';


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
-- Name: TABLE solid_queue_blocked_executions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_blocked_executions IS '[キュー] 同時実行の上限で待たされているジョブ';


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
-- Name: TABLE solid_queue_claimed_executions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_claimed_executions IS '[キュー] ワーカーが取り出して実行中のジョブ';


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
-- Name: TABLE solid_queue_failed_executions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_failed_executions IS '[キュー] 失敗したジョブと、その例外';


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
-- Name: TABLE solid_queue_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_jobs IS '[キュー] Solid Queue に登録したジョブ。イベントもジョブとして登録する';


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
-- Name: TABLE solid_queue_pauses; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_pauses IS '[キュー] 一時停止中のキュー';


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
-- Name: TABLE solid_queue_processes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_processes IS '[キュー] 動いているワーカーなどのプロセスと、最後の生存通知';


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
-- Name: TABLE solid_queue_ready_executions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_ready_executions IS '[キュー] すぐに実行できるジョブの待ち行列';


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
-- Name: TABLE solid_queue_recurring_executions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_recurring_executions IS '[キュー] 定期実行のタスクから登録したジョブの記録';


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
-- Name: TABLE solid_queue_recurring_tasks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_recurring_tasks IS '[キュー] 定期実行するタスクの定義';


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
-- Name: TABLE solid_queue_scheduled_executions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_scheduled_executions IS '[キュー] 実行の時刻を待つジョブ';


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
-- Name: TABLE solid_queue_semaphores; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.solid_queue_semaphores IS '[キュー] 同時実行の上限を数えるセマフォ';


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
-- Name: stock_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_movements (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    item_id uuid NOT NULL,
    type character varying NOT NULL,
    quantity integer NOT NULL,
    reason character varying,
    allocation_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT stock_movements_allocation_by_type CHECK ((((type)::text = ANY (ARRAY['allocate'::text, 'deallocate'::text, 'ship'::text])) = (allocation_id IS NOT NULL))),
    CONSTRAINT stock_movements_quantity_positive CHECK ((quantity > 0)),
    CONSTRAINT stock_movements_type_check CHECK (((type)::text = ANY (ARRAY['inbound'::text, 'outbound'::text, 'allocate'::text, 'deallocate'::text, 'ship'::text])))
);

ALTER TABLE ONLY public.stock_movements FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE stock_movements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.stock_movements IS '[在庫] 在庫移動履歴。在庫を変えるたびに追記し、書き換えない';


--
-- Name: stocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stocks (
    id uuid DEFAULT uuidv7() NOT NULL,
    owner_tenant_id uuid NOT NULL,
    item_id uuid NOT NULL,
    on_hand integer DEFAULT 0 NOT NULL,
    allocated integer DEFAULT 0 NOT NULL,
    safety_stock integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT stocks_available_non_negative CHECK (((allocated >= 0) AND (on_hand >= allocated))),
    CONSTRAINT stocks_safety_stock_non_negative CHECK ((safety_stock >= 0))
);

ALTER TABLE ONLY public.stocks FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE stocks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.stocks IS '[在庫] 品目ごとの在庫。手持ち・引当済み・安全在庫の数量を持つ';


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
-- Name: TABLE tenants; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.tenants IS '[取引関係] テナント。名前と、取引関係の相手の指定に使う取引用コードを持つ';


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
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.users IS '[取引関係] テナントのユーザー。ログインの資格情報とセッションの世代を持つ';


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
-- Name: allocations allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.allocations
    ADD CONSTRAINT allocations_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: customer_part_mappings customer_part_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_part_mappings
    ADD CONSTRAINT customer_part_mappings_pkey PRIMARY KEY (id);


--
-- Name: inbound_shipment_lines inbound_shipment_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_shipment_lines
    ADD CONSTRAINT inbound_shipment_lines_pkey PRIMARY KEY (id);


--
-- Name: inbound_shipments inbound_shipments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_shipments
    ADD CONSTRAINT inbound_shipments_pkey PRIMARY KEY (id);


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
-- Name: shipment_lines shipment_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_lines
    ADD CONSTRAINT shipment_lines_pkey PRIMARY KEY (id);


--
-- Name: shipment_request_lines shipment_request_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_request_lines
    ADD CONSTRAINT shipment_request_lines_pkey PRIMARY KEY (id);


--
-- Name: shipment_requests shipment_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_requests
    ADD CONSTRAINT shipment_requests_pkey PRIMARY KEY (id);


--
-- Name: shipments shipments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_pkey PRIMARY KEY (id);


--
-- Name: shipping_instructions shipping_instructions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipping_instructions
    ADD CONSTRAINT shipping_instructions_pkey PRIMARY KEY (id);


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
-- Name: stock_movements stock_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_pkey PRIMARY KEY (id);


--
-- Name: stocks stocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_pkey PRIMARY KEY (id);


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
-- Name: idx_on_inbound_shipment_id_purchase_order_line_id_3e46b99bab; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_inbound_shipment_id_purchase_order_line_id_3e46b99bab ON public.inbound_shipment_lines USING btree (inbound_shipment_id, purchase_order_line_id);


--
-- Name: idx_on_owner_tenant_id_inbound_shipment_id_c08904320e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_owner_tenant_id_inbound_shipment_id_c08904320e ON public.inbound_shipment_lines USING btree (owner_tenant_id, inbound_shipment_id);


--
-- Name: idx_on_owner_tenant_id_purchase_order_id_bb29b0b793; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_owner_tenant_id_purchase_order_id_bb29b0b793 ON public.purchase_order_lines USING btree (owner_tenant_id, purchase_order_id);


--
-- Name: idx_on_owner_tenant_id_purchase_order_id_f190365cb3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_owner_tenant_id_purchase_order_id_f190365cb3 ON public.inbound_shipments USING btree (owner_tenant_id, purchase_order_id);


--
-- Name: idx_on_owner_tenant_id_purchase_order_line_id_b4d8e1aa74; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_owner_tenant_id_purchase_order_line_id_b4d8e1aa74 ON public.inbound_shipment_lines USING btree (owner_tenant_id, purchase_order_line_id);


--
-- Name: idx_on_owner_tenant_id_shipment_request_id_1227c60102; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_owner_tenant_id_shipment_request_id_1227c60102 ON public.shipping_instructions USING btree (owner_tenant_id, shipment_request_id);


--
-- Name: idx_on_owner_tenant_id_shipment_request_id_1756bb9570; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_owner_tenant_id_shipment_request_id_1756bb9570 ON public.shipment_request_lines USING btree (owner_tenant_id, shipment_request_id);


--
-- Name: idx_on_owner_tenant_id_shipment_request_line_id_7e3e49cc79; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_owner_tenant_id_shipment_request_line_id_7e3e49cc79 ON public.shipment_lines USING btree (owner_tenant_id, shipment_request_line_id);


--
-- Name: idx_on_purchase_order_id_part_number_bda45e1f84; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_purchase_order_id_part_number_bda45e1f84 ON public.purchase_order_lines USING btree (purchase_order_id, part_number);


--
-- Name: index_allocations_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_allocations_on_owner_tenant_id_and_id ON public.allocations USING btree (owner_tenant_id, id);


--
-- Name: index_allocations_on_owner_tenant_id_and_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_allocations_on_owner_tenant_id_and_item_id ON public.allocations USING btree (owner_tenant_id, item_id);


--
-- Name: index_allocations_on_sales_order_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_allocations_on_sales_order_line_id ON public.allocations USING btree (sales_order_line_id);


--
-- Name: index_audit_logs_on_event_receipt; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_logs_on_event_receipt ON public.audit_logs USING btree (owner_tenant_id, causation_id, action) WHERE ((action)::text = 'event.received'::text);


--
-- Name: index_audit_logs_on_owner_tenant_id_and_correlation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_owner_tenant_id_and_correlation_id ON public.audit_logs USING btree (owner_tenant_id, correlation_id);


--
-- Name: index_audit_logs_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_logs_on_owner_tenant_id_and_id ON public.audit_logs USING btree (owner_tenant_id, id);


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
-- Name: index_inbound_shipment_lines_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_shipment_lines_on_owner_tenant_id_and_id ON public.inbound_shipment_lines USING btree (owner_tenant_id, id);


--
-- Name: index_inbound_shipments_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_shipments_on_owner_tenant_id_and_id ON public.inbound_shipments USING btree (owner_tenant_id, id);


--
-- Name: index_inbound_shipments_on_shipment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_shipments_on_shipment_id ON public.inbound_shipments USING btree (shipment_id);


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
-- Name: index_shipment_lines_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipment_lines_on_owner_tenant_id_and_id ON public.shipment_lines USING btree (owner_tenant_id, id);


--
-- Name: index_shipment_lines_on_owner_tenant_id_and_shipment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shipment_lines_on_owner_tenant_id_and_shipment_id ON public.shipment_lines USING btree (owner_tenant_id, shipment_id);


--
-- Name: index_shipment_lines_on_shipment_request_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipment_lines_on_shipment_request_line_id ON public.shipment_lines USING btree (shipment_request_line_id);


--
-- Name: index_shipment_request_lines_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipment_request_lines_on_owner_tenant_id_and_id ON public.shipment_request_lines USING btree (owner_tenant_id, id);


--
-- Name: index_shipment_request_lines_on_sales_order_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipment_request_lines_on_sales_order_line_id ON public.shipment_request_lines USING btree (sales_order_line_id);


--
-- Name: index_shipment_requests_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipment_requests_on_owner_tenant_id_and_id ON public.shipment_requests USING btree (owner_tenant_id, id);


--
-- Name: index_shipment_requests_on_sales_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipment_requests_on_sales_order_id ON public.shipment_requests USING btree (sales_order_id);


--
-- Name: index_shipments_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipments_on_owner_tenant_id_and_id ON public.shipments USING btree (owner_tenant_id, id);


--
-- Name: index_shipments_on_owner_tenant_id_and_shipment_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shipments_on_owner_tenant_id_and_shipment_request_id ON public.shipments USING btree (owner_tenant_id, shipment_request_id);


--
-- Name: index_shipments_on_owner_tenant_id_and_shipping_instruction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_shipments_on_owner_tenant_id_and_shipping_instruction_id ON public.shipments USING btree (owner_tenant_id, shipping_instruction_id);


--
-- Name: index_shipments_on_shipment_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipments_on_shipment_request_id ON public.shipments USING btree (shipment_request_id);


--
-- Name: index_shipping_instructions_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipping_instructions_on_owner_tenant_id_and_id ON public.shipping_instructions USING btree (owner_tenant_id, id);


--
-- Name: index_shipping_instructions_one_active_per_request; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_shipping_instructions_one_active_per_request ON public.shipping_instructions USING btree (shipment_request_id) WHERE ((status)::text = 'active'::text);


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
-- Name: index_stock_movements_on_owner_tenant_id_and_allocation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_movements_on_owner_tenant_id_and_allocation_id ON public.stock_movements USING btree (owner_tenant_id, allocation_id);


--
-- Name: index_stock_movements_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stock_movements_on_owner_tenant_id_and_id ON public.stock_movements USING btree (owner_tenant_id, id);


--
-- Name: index_stock_movements_on_owner_tenant_id_and_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_movements_on_owner_tenant_id_and_item_id ON public.stock_movements USING btree (owner_tenant_id, item_id);


--
-- Name: index_stocks_on_owner_tenant_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stocks_on_owner_tenant_id_and_id ON public.stocks USING btree (owner_tenant_id, id);


--
-- Name: index_stocks_on_owner_tenant_id_and_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stocks_on_owner_tenant_id_and_item_id ON public.stocks USING btree (owner_tenant_id, item_id);


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
-- Name: audit_logs audit_logs_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_logs_append_only BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.audit_logs_append_only();


--
-- Name: audit_logs audit_logs_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_logs_no_truncate BEFORE TRUNCATE ON public.audit_logs FOR EACH STATEMENT EXECUTE FUNCTION public.audit_logs_append_only();


--
-- Name: users users_bump_session_version; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_bump_session_version BEFORE UPDATE OF password_digest ON public.users FOR EACH ROW WHEN (((old.password_digest)::text IS DISTINCT FROM (new.password_digest)::text)) EXECUTE FUNCTION public.bump_session_version();


--
-- Name: stocks fk_rails_08def19f32; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT fk_rails_08def19f32 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: inbound_shipment_lines fk_rails_0d7637b148; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_shipment_lines
    ADD CONSTRAINT fk_rails_0d7637b148 FOREIGN KEY (owner_tenant_id, purchase_order_line_id) REFERENCES public.purchase_order_lines(owner_tenant_id, id);


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
-- Name: shipment_request_lines fk_rails_1a94872e8b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_request_lines
    ADD CONSTRAINT fk_rails_1a94872e8b FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: shipments fk_rails_1f1c050f7b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT fk_rails_1f1c050f7b FOREIGN KEY (owner_tenant_id, shipping_instruction_id) REFERENCES public.shipping_instructions(owner_tenant_id, id);


--
-- Name: inbound_shipments fk_rails_2414e5e331; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_shipments
    ADD CONSTRAINT fk_rails_2414e5e331 FOREIGN KEY (owner_tenant_id, purchase_order_id) REFERENCES public.purchase_orders(owner_tenant_id, id);


--
-- Name: allocations fk_rails_24278b0998; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.allocations
    ADD CONSTRAINT fk_rails_24278b0998 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


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
-- Name: inbound_shipment_lines fk_rails_305b73d616; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_shipment_lines
    ADD CONSTRAINT fk_rails_305b73d616 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: audit_logs fk_rails_32a1dd949f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_rails_32a1dd949f FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


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
-- Name: shipments fk_rails_55762b904e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT fk_rails_55762b904e FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: shipment_request_lines fk_rails_5c0bad21b3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_request_lines
    ADD CONSTRAINT fk_rails_5c0bad21b3 FOREIGN KEY (owner_tenant_id, shipment_request_id) REFERENCES public.shipment_requests(owner_tenant_id, id);


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
-- Name: inbound_shipments fk_rails_6c71ad6bd1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_shipments
    ADD CONSTRAINT fk_rails_6c71ad6bd1 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: sales_order_lines fk_rails_6ea4e05c77; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_lines
    ADD CONSTRAINT fk_rails_6ea4e05c77 FOREIGN KEY (owner_tenant_id, item_id) REFERENCES public.items(owner_tenant_id, id);


--
-- Name: shipping_instructions fk_rails_7b67c8f9e5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipping_instructions
    ADD CONSTRAINT fk_rails_7b67c8f9e5 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


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
-- Name: shipment_lines fk_rails_8d83f67036; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_lines
    ADD CONSTRAINT fk_rails_8d83f67036 FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: shipping_instructions fk_rails_9036b71040; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipping_instructions
    ADD CONSTRAINT fk_rails_9036b71040 FOREIGN KEY (owner_tenant_id, shipment_request_id) REFERENCES public.shipment_requests(owner_tenant_id, id);


--
-- Name: solid_queue_claimed_executions fk_rails_9cfe4d4944; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT fk_rails_9cfe4d4944 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: shipment_lines fk_rails_a70de72e97; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_lines
    ADD CONSTRAINT fk_rails_a70de72e97 FOREIGN KEY (owner_tenant_id, shipment_id) REFERENCES public.shipments(owner_tenant_id, id);


--
-- Name: stock_movements fk_rails_a7f7ea137e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_rails_a7f7ea137e FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: shipment_requests fk_rails_b4d07768dc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_requests
    ADD CONSTRAINT fk_rails_b4d07768dc FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: stock_movements fk_rails_b61766ec6b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_rails_b61766ec6b FOREIGN KEY (owner_tenant_id, item_id) REFERENCES public.stocks(owner_tenant_id, item_id);


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
-- Name: stock_movements fk_rails_cca864944b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_rails_cca864944b FOREIGN KEY (owner_tenant_id, allocation_id) REFERENCES public.allocations(owner_tenant_id, id);


--
-- Name: sales_order_lines fk_rails_cfa1b9b0af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_lines
    ADD CONSTRAINT fk_rails_cfa1b9b0af FOREIGN KEY (owner_tenant_id) REFERENCES public.tenants(id);


--
-- Name: inbound_shipment_lines fk_rails_d0d168c0d6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_shipment_lines
    ADD CONSTRAINT fk_rails_d0d168c0d6 FOREIGN KEY (owner_tenant_id, inbound_shipment_id) REFERENCES public.inbound_shipments(owner_tenant_id, id);


--
-- Name: customer_part_mappings fk_rails_d76de7871e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_part_mappings
    ADD CONSTRAINT fk_rails_d76de7871e FOREIGN KEY (owner_tenant_id, item_id) REFERENCES public.items(owner_tenant_id, id);


--
-- Name: allocations fk_rails_e0d854f9c6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.allocations
    ADD CONSTRAINT fk_rails_e0d854f9c6 FOREIGN KEY (owner_tenant_id, item_id) REFERENCES public.stocks(owner_tenant_id, item_id);


--
-- Name: shipment_lines fk_rails_e56eb8ed16; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_lines
    ADD CONSTRAINT fk_rails_e56eb8ed16 FOREIGN KEY (owner_tenant_id, shipment_request_line_id) REFERENCES public.shipment_request_lines(owner_tenant_id, id);


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
-- Name: shipments fk_rails_f9cec7c937; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT fk_rails_f9cec7c937 FOREIGN KEY (owner_tenant_id, shipment_request_id) REFERENCES public.shipment_requests(owner_tenant_id, id);


--
-- Name: allocations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.allocations ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_part_mappings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_part_mappings ENABLE ROW LEVEL SECURITY;

--
-- Name: inbound_shipment_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inbound_shipment_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: inbound_shipments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inbound_shipments ENABLE ROW LEVEL SECURITY;

--
-- Name: items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;

--
-- Name: allocations owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.allocations USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: audit_logs owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.audit_logs USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: customer_part_mappings owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.customer_part_mappings USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: inbound_shipment_lines owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.inbound_shipment_lines USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: inbound_shipments owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.inbound_shipments USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


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
-- Name: shipment_lines owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.shipment_lines USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: shipment_request_lines owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.shipment_request_lines USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: shipment_requests owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.shipment_requests USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: shipments owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.shipments USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: shipping_instructions owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.shipping_instructions USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: stock_movements owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.stock_movements USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


--
-- Name: stocks owner_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY owner_write ON public.stocks USING ((owner_tenant_id = public.current_tenant_id())) WITH CHECK ((owner_tenant_id = public.current_tenant_id()));


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
-- Name: shipment_lines partner_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY partner_read ON public.shipment_lines FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.shipments s
  WHERE (s.id = shipment_lines.shipment_id))));


--
-- Name: shipments partner_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY partner_read ON public.shipments FOR SELECT USING (((buyer_tenant_id = public.current_tenant_id()) AND public.partnership_active(owner_tenant_id, buyer_tenant_id)));


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
-- Name: shipment_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shipment_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: shipment_request_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shipment_request_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: shipment_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shipment_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: shipments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shipments ENABLE ROW LEVEL SECURITY;

--
-- Name: shipping_instructions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shipping_instructions ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: stocks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stocks ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261011000000'),
('20261010000000'),
('20261009000000'),
('20261008000900'),
('20261008000800'),
('20261008000700'),
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


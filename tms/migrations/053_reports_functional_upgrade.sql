-- Update 059: functional Reports. Run after 051; 052 is optional.
-- Self-contained CREATE OR REPLACE: works whether 052 was installed or not.
-- Invoker rights preserve RLS. No business data or existing policy changes.
BEGIN;
DO $$
BEGIN
    IF to_regprocedure('public.current_user_access_enabled()') IS NULL
       OR to_regprocedure('public.is_company_user()') IS NULL
       OR to_regclass('public.project_scoops') IS NULL
       OR to_regclass('public.supplier_po_versions') IS NULL
       OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='projects' AND column_name='project_manager_resource_id') THEN
        RAISE EXCEPTION 'Reports 059 requires the existing operational schema and access helpers. Complete the earlier TMS migrations before applying 053.';
    END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.tms_report(
    p_type TEXT DEFAULT 'projects', p_filters JSONB DEFAULT '{}'::jsonb,
    p_offset INTEGER DEFAULT 0, p_limit INTEGER DEFAULT 50,
    p_sort TEXT DEFAULT 'name', p_desc BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = public
AS $$
DECLARE result JSONB; from_date DATE; to_date DATE; scope TEXT;
    date_basis TEXT; group_by TEXT; issue_filter TEXT; selected_cost_basis TEXT;
    filter_client_id UUID; filter_account_id UUID; filter_pm_id UUID; filter_resource_id UUID;
    margin_min NUMERIC; margin_max NUMERIC;
BEGIN
    IF NOT COALESCE(public.is_company_user(), FALSE)
       OR NOT COALESCE(public.current_user_access_enabled(), FALSE) THEN
        RAISE EXCEPTION 'Company report access required' USING ERRCODE = '42501';
    END IF;
    IF p_type IS NULL OR p_type NOT IN ('projects','jobs','margin')
       OR p_sort IS NULL OR p_sort NOT IN ('name','date','status','client','client_value','cost','profit','margin')
       OR p_offset IS NULL OR p_offset < 0 OR p_limit IS NULL OR p_limit < 1 OR p_limit > 10000
       OR p_desc IS NULL OR p_filters IS NULL OR jsonb_typeof(p_filters) <> 'object' THEN
        RAISE EXCEPTION 'Invalid report parameters';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_filters) k
               WHERE k NOT IN ('search','client','account','pm','status','statuses','from','to','scope','client_id','account_id','pm_id','resource_id','source_language','target_language','service','currency','cost_basis','issue','margin_min','margin_max','date_basis','group_by')) THEN
        RAISE EXCEPTION 'Unsupported report filter';
    END IF;
    from_date := NULLIF(p_filters->>'from','')::date;
    to_date := NULLIF(p_filters->>'to','')::date;
    scope := COALESCE(p_filters->>'scope','active');
    IF scope NOT IN ('active','all') OR from_date > to_date THEN
        RAISE EXCEPTION 'Invalid scope or date range';
    END IF;

    date_basis := COALESCE(NULLIF(p_filters->>'date_basis',''), CASE WHEN p_type='jobs' THEN 'deadline' ELSE 'project' END);
    group_by := COALESCE(NULLIF(p_filters->>'group_by',''),'none');
    issue_filter := COALESCE(NULLIF(p_filters->>'issue',''),'all');
    selected_cost_basis := COALESCE(NULLIF(p_filters->>'cost_basis',''),'all');
    filter_client_id := NULLIF(p_filters->>'client_id','')::uuid;
    filter_account_id := NULLIF(p_filters->>'account_id','')::uuid;
    filter_pm_id := NULLIF(p_filters->>'pm_id','')::uuid;
    filter_resource_id := NULLIF(p_filters->>'resource_id','')::uuid;
    margin_min := NULLIF(p_filters->>'margin_min','')::numeric;
    margin_max := NULLIF(p_filters->>'margin_max','')::numeric;
    IF date_basis NOT IN ('project','deadline')
       OR group_by NOT IN ('none','client','account','pm','month','language','resource','service')
       OR (p_type<>'jobs' AND (group_by IN ('resource','service') OR filter_resource_id IS NOT NULL))
       OR (p_type='projects' AND group_by='language')
       OR issue_filter NOT IN ('all','blocked','estimates','unknown_cost','po_conflict','currency_mismatch','unallocated','no_jobs')
       OR selected_cost_basis NOT IN ('all','po','estimate','unknown')
       OR margin_min > margin_max
       OR (p_filters ? 'statuses' AND jsonb_typeof(p_filters->'statuses') <> 'array')
       OR (p_sort IN ('client_value','cost','profit') AND NULLIF(p_filters->>'currency','') IS NULL)
       OR (p_type='jobs' AND (p_sort IN ('client_value','profit','margin') OR margin_min IS NOT NULL OR margin_max IS NOT NULL)) THEN
        RAISE EXCEPTION 'Invalid report options. Monetary sorting requires a currency; Job reports have no client margin.';
    END IF;

    WITH project_base AS MATERIALIZED (
        SELECT p.id, p.project_number, COALESCE(NULLIF(p.display_name,''),p.project_number) name,
            p.project_date, p.deadline, p.status, p.currency, p.project_manager pm,
            p.client_id, p.account_id, p.project_manager_resource_id pm_id,
            c.name client, a.name account
        FROM public.projects p
        LEFT JOIN public.clients c ON c.id = p.client_id
        LEFT JOIN public.client_accounts a ON a.id = p.account_id
        WHERE (scope = 'all' OR p.status <> 'Cancelled')
          AND (filter_client_id IS NULL OR p.client_id=filter_client_id)
          AND (filter_account_id IS NULL OR p.account_id=filter_account_id)
          AND (filter_pm_id IS NULL OR p.project_manager_resource_id=filter_pm_id)
          AND (COALESCE(p_filters->>'client','') = '' OR c.name ILIKE '%' || (p_filters->>'client') || '%')
          AND (COALESCE(p_filters->>'account','') = '' OR a.name ILIKE '%' || (p_filters->>'account') || '%')
          AND (COALESCE(p_filters->>'pm','') = '' OR p.project_manager ILIKE '%' || (p_filters->>'pm') || '%')
    ), scoop_base AS MATERIALIZED (
        SELECT s.* FROM public.project_scoops s JOIN project_base p ON p.id=s.project_id
        WHERE scope='all' OR (s.active AND s.status <> 'Cancelled')
    ), job_base AS MATERIALIZED (
        SELECT j.*, po.id po_id, po.po_number, po.current_version po_version,
            COALESCE(po.currency,j.supplier_currency) cost_currency,
            CASE WHEN po.id IS NOT NULL THEN po.total
                 WHEN j.supplier_rate IS NOT NULL THEN j.supplier_amount ELSE NULL END cost,
            CASE WHEN po.id IS NOT NULL THEN 'PO commitment'
                 WHEN j.supplier_rate IS NOT NULL THEN 'Estimate' ELSE 'Unknown' END cost_basis,
            COALESCE(po.candidates,0) active_po_count,
            (po.id IS NOT NULL AND (v.id IS NULL OR
                v.snapshot->'total' IS DISTINCT FROM to_jsonb(po.total) OR
                v.snapshot->>'currency' IS DISTINCT FROM po.currency)) po_warning,
            COALESCE(NULLIF(r.legal_name,''),NULLIF(r.company_name,''),r.internal_number) resource_name
        FROM public.project_jobs j JOIN project_base p ON p.id=j.project_id
        LEFT JOIN public.resources r ON r.id=j.resource_id
        LEFT JOIN LATERAL (
            SELECT x.*, count(*) OVER () candidates FROM public.supplier_purchase_orders x
            WHERE x.job_id=j.id AND x.status IN ('Issued','Acknowledged')
            ORDER BY x.created_at DESC, x.id DESC LIMIT 1
        ) po ON TRUE
        LEFT JOIN public.supplier_po_versions v ON v.purchase_order_id=po.id AND v.version_number=po.current_version
        WHERE (scope='all' OR j.status NOT IN ('Cancelled','Declined'))
          AND (j.project_scoop_id IS NULL OR EXISTS (SELECT 1 FROM scoop_base s WHERE s.id=j.project_scoop_id))
    ), scoop_metrics AS MATERIALIZED (
        SELECT s.id, s.project_id, s.scoop_number name, s.status, s.source_language, s.target_language,
            s.price client_value, s.deadline, s.active, p.currency,
            (SELECT count(*) FROM job_base j WHERE j.project_id=p.id AND j.project_scoop_id IS NULL) unallocated_job_count,
            (SELECT count(*) FROM job_base j WHERE j.project_scoop_id=s.id) job_count,
            (SELECT count(*) FROM public.project_jobs j WHERE j.project_scoop_id=s.id AND j.status IN ('Cancelled','Declined') AND scope='active') excluded_job_count,
            COALESCE((SELECT jsonb_object_agg(x.cost_currency,x.amount) FROM (
                SELECT COALESCE(NULLIF(j.cost_currency,''),'Unknown') cost_currency, sum(j.cost) amount
                FROM job_base j WHERE j.project_scoop_id=s.id GROUP BY 1) x),'{}'::jsonb) costs,
            (SELECT count(*) FROM job_base j WHERE j.project_scoop_id=s.id AND j.cost_basis='Estimate') estimate_count,
            (SELECT count(*) FROM job_base j WHERE j.project_scoop_id=s.id AND j.cost IS NULL) unknown_cost_count,
            (SELECT count(*) FROM job_base j WHERE j.project_scoop_id=s.id AND (j.po_warning OR j.active_po_count>1)) po_warning_count,
            (SELECT count(*) FROM job_base j WHERE j.project_scoop_id=s.id AND (j.cost_currency IS DISTINCT FROM p.currency OR NULLIF(j.cost_currency,'') IS NULL)) currency_warning_count,
            (SELECT sum(j.cost) FROM job_base j WHERE j.project_scoop_id=s.id) numeric_cost
        FROM scoop_base s JOIN project_base p ON p.id=s.project_id
    ), project_metrics AS MATERIALIZED (
        SELECT p.*,
            (SELECT sum(s.client_value) FROM scoop_metrics s WHERE s.project_id=p.id) client_value,
            (SELECT count(*) FROM scoop_metrics s WHERE s.project_id=p.id) scoop_count,
            (SELECT count(*) FROM scoop_metrics s WHERE s.project_id=p.id AND s.job_count=0) empty_scoop_count,
            (SELECT count(*) FROM job_base j WHERE j.project_id=p.id) job_count,
            (SELECT count(*) FROM public.project_jobs j WHERE j.project_id=p.id AND j.status IN ('Cancelled','Declined') AND scope='active') excluded_job_count,
            (SELECT count(*) FROM job_base j WHERE j.project_id=p.id AND j.cost_basis='Estimate') estimate_count,
            (SELECT count(*) FROM job_base j WHERE j.project_id=p.id AND j.cost IS NULL) unknown_cost_count,
            (SELECT count(*) FROM job_base j WHERE j.project_id=p.id AND (j.po_warning OR j.active_po_count>1)) po_warning_count,
            (SELECT count(*) FROM job_base j WHERE j.project_id=p.id AND (j.cost_currency IS DISTINCT FROM p.currency OR NULLIF(j.cost_currency,'') IS NULL)) currency_warning_count,
            (SELECT count(*) FROM job_base j WHERE j.project_id=p.id AND j.project_scoop_id IS NULL) unallocated_job_count,
            COALESCE((SELECT jsonb_object_agg(x.cost_currency,x.amount) FROM (
                SELECT COALESCE(NULLIF(j.cost_currency,''),'Unknown') cost_currency,sum(j.cost) amount
                FROM job_base j WHERE j.project_id=p.id GROUP BY 1) x),'{}'::jsonb) costs,
            (SELECT sum(j.cost) FROM job_base j WHERE j.project_id=p.id) numeric_cost
        FROM project_base p
    ), raw_rows AS (
        SELECT p.id,p.id project_id,p.name,p.status,p.client,p.account,p.pm,
            (CASE WHEN date_basis='deadline' THEN (p.deadline AT TIME ZONE 'UTC')::date ELSE p.project_date END)::text date,p.currency,
            to_jsonb(p) - 'numeric_cost' || jsonb_build_object('project_id',p.id,'date',CASE WHEN date_basis='deadline' THEN (p.deadline AT TIME ZONE 'UTC')::date ELSE p.project_date END,
                'profit',CASE WHEN p.scoop_count>0 AND p.empty_scoop_count=0 AND p.job_count>0 AND p.unknown_cost_count=0 AND p.po_warning_count=0 AND p.currency_warning_count=0 AND p.unallocated_job_count=0 AND NULLIF(p.currency,'') IS NOT NULL THEN p.client_value-p.numeric_cost END) row
        FROM project_metrics p WHERE p_type='projects'
        UNION ALL
        SELECT s.id,p.id,s.name,s.status,p.client,p.account,p.pm,(CASE WHEN date_basis='deadline' THEN (s.deadline AT TIME ZONE 'UTC')::date ELSE p.project_date END)::text,p.currency,
            to_jsonb(s) - 'numeric_cost' || jsonb_build_object('project_id',p.id,'project_name',p.name,'project_number',p.project_number,'client',p.client,'client_id',p.client_id,'account',p.account,'account_id',p.account_id,'pm',p.pm,'pm_id',p.pm_id,'date',CASE WHEN date_basis='deadline' THEN (s.deadline AT TIME ZONE 'UTC')::date ELSE p.project_date END,
                'profit',CASE WHEN s.job_count>0 AND s.unallocated_job_count=0 AND s.unknown_cost_count=0 AND s.po_warning_count=0 AND s.currency_warning_count=0 AND NULLIF(p.currency,'') IS NOT NULL THEN s.client_value-s.numeric_cost END)
        FROM scoop_metrics s JOIN project_base p ON p.id=s.project_id WHERE p_type='margin'
        UNION ALL
        SELECT j.id,p.id,j.job_number,j.status,p.client,p.account,p.pm,
            (CASE WHEN date_basis='project' THEN p.project_date ELSE (j.deadline AT TIME ZONE 'UTC')::date END)::text,j.cost_currency,
            jsonb_build_object('id',j.id,'project_id',p.id,'project_name',p.name,'project_number',p.project_number,'scoop_id',j.project_scoop_id,
                'scoop_number',(SELECT s.scoop_number FROM scoop_base s WHERE s.id=j.project_scoop_id),'resource_id',j.resource_id,
                'name',j.job_number,'status',j.status,'client',p.client,'client_id',p.client_id,'account',p.account,'account_id',p.account_id,'pm',p.pm,'pm_id',p.pm_id,
                'date',CASE WHEN date_basis='project' THEN p.project_date ELSE (j.deadline AT TIME ZONE 'UTC')::date END,'deadline',j.deadline,
                'service',j.service_type,'source_language',j.source_language,'target_language',j.target_language,
                'resource',j.resource_name,'quantity',j.quantity,'unit',j.unit,
                'costs',jsonb_build_object(COALESCE(NULLIF(j.cost_currency,''),'Unknown'),j.cost),
                'currency',j.cost_currency,'cost_basis',j.cost_basis,'po_id',j.po_id,'po_number',j.po_number,'po_version',j.po_version,
                'active_po_count',j.active_po_count,'estimate_count',CASE WHEN j.cost_basis='Estimate' THEN 1 ELSE 0 END,
                'unknown_cost_count',CASE WHEN j.cost IS NULL THEN 1 ELSE 0 END,
                'po_warning_count',CASE WHEN j.po_warning OR j.active_po_count>1 THEN 1 ELSE 0 END,
                'currency_warning_count',CASE WHEN NULLIF(j.cost_currency,'') IS NULL THEN 1 ELSE 0 END)
        FROM job_base j JOIN project_base p ON p.id=j.project_id WHERE p_type='jobs'
    ), enriched AS MATERIALIZED (
        SELECT r.*, row || jsonb_build_object(
            'margin',CASE WHEN (row->>'client_value')::numeric <> 0 THEN round((row->>'profit')::numeric/(row->>'client_value')::numeric*100,2) END,
            'blocking_issues',to_jsonb(array_remove(ARRAY[
                CASE WHEN COALESCE((row->>'unknown_cost_count')::int,0)>0 THEN 'unknown_cost' END,
                CASE WHEN COALESCE((row->>'po_warning_count')::int,0)>0 THEN 'po_conflict' END,
                CASE WHEN COALESCE((row->>'currency_warning_count')::int,0)>0 THEN 'currency_mismatch' END,
                CASE WHEN COALESCE((row->>'unallocated_job_count')::int,0)>0 THEN 'unallocated' END,
                CASE WHEN p_type<>'jobs' AND (COALESCE((row->>'job_count')::int,0)=0 OR COALESCE((row->>'empty_scoop_count')::int,0)>0) THEN 'no_jobs' END,
                CASE WHEN p_type='projects' AND COALESCE((row->>'scoop_count')::int,0)=0 THEN 'no_scoops' END
            ],NULL))) detail
        FROM raw_rows r
    ), filtered AS MATERIALIZED (
        SELECT * FROM enriched r
        WHERE (COALESCE(p_filters->>'status','')='' OR r.status=p_filters->>'status')
          AND (COALESCE(jsonb_array_length(p_filters->'statuses'),0)=0 OR (p_filters->'statuses') ? r.status)
          AND (from_date IS NULL OR r.date::date>=from_date)
          AND (to_date IS NULL OR r.date::date<=to_date)
          AND (COALESCE(p_filters->>'currency','')='' OR r.currency=p_filters->>'currency')
          AND (filter_resource_id IS NULL OR r.row->>'resource_id'=filter_resource_id::text)
          AND (margin_min IS NULL OR (r.detail->>'margin')::numeric>=margin_min)
          AND (margin_max IS NULL OR (r.detail->>'margin')::numeric<=margin_max)
          AND (issue_filter='all'
            OR (issue_filter='blocked' AND jsonb_array_length(r.detail->'blocking_issues')>0)
            OR (issue_filter='estimates' AND COALESCE((r.row->>'estimate_count')::int,0)>0)
            OR (r.detail->'blocking_issues') ? issue_filter)
          AND (selected_cost_basis='all' OR EXISTS (SELECT 1 FROM job_base j
            WHERE j.project_id=r.project_id AND (p_type='projects' OR (p_type='margin' AND j.project_scoop_id=r.id) OR (p_type='jobs' AND j.id=r.id))
              AND j.cost_basis=CASE selected_cost_basis WHEN 'po' THEN 'PO commitment' WHEN 'estimate' THEN 'Estimate' ELSE 'Unknown' END))
          AND (CASE WHEN p_type='projects' THEN
            ((COALESCE(p_filters->>'source_language','')='' AND COALESCE(p_filters->>'target_language','')='') OR EXISTS(
              SELECT 1 FROM scoop_base s WHERE s.project_id=r.id
                AND (COALESCE(p_filters->>'source_language','')='' OR s.source_language=p_filters->>'source_language')
                AND (COALESCE(p_filters->>'target_language','')='' OR s.target_language=p_filters->>'target_language')))
            ELSE (COALESCE(p_filters->>'source_language','')='' OR r.row->>'source_language'=p_filters->>'source_language')
             AND (COALESCE(p_filters->>'target_language','')='' OR r.row->>'target_language'=p_filters->>'target_language') END)
          AND (COALESCE(p_filters->>'service','')='' OR EXISTS(SELECT 1 FROM job_base j WHERE j.project_id=r.project_id
            AND (p_type='projects' OR (p_type='margin' AND j.project_scoop_id=r.id) OR (p_type='jobs' AND j.id=r.id))
            AND j.service_type=p_filters->>'service'))
          AND (COALESCE(p_filters->>'search','')='' OR
            concat_ws(' ',r.name,r.row->>'project_number',r.client,r.account,r.pm,r.row->>'resource',r.row->>'po_number',r.row->>'scoop_number',r.row->>'service',r.row->>'project_name',r.row->>'source_language',r.row->>'target_language') ILIKE '%'||(p_filters->>'search')||'%'
            OR (p_type='projects' AND EXISTS(SELECT 1 FROM scoop_base s WHERE s.project_id=r.id
                AND concat_ws(' ',s.scoop_number,s.source_language,s.target_language) ILIKE '%'||(p_filters->>'search')||'%'))
            OR (p_type<>'jobs' AND EXISTS(SELECT 1 FROM job_base j WHERE j.project_id=r.project_id AND (p_type='projects' OR j.project_scoop_id=r.id)
                AND concat_ws(' ',j.job_number,j.resource_name,j.service_type,j.po_number,j.source_language,j.target_language) ILIKE '%'||(p_filters->>'search')||'%')))
    ), ordered AS (
        SELECT *,row_number() OVER (ORDER BY
            CASE WHEN NOT p_desc THEN CASE p_sort WHEN 'name' THEN name WHEN 'date' THEN date WHEN 'status' THEN status WHEN 'client' THEN client END END ASC NULLS LAST,
            CASE WHEN p_desc THEN CASE p_sort WHEN 'name' THEN name WHEN 'date' THEN date WHEN 'status' THEN status WHEN 'client' THEN client END END DESC NULLS LAST,
            CASE WHEN NOT p_desc THEN CASE p_sort WHEN 'client_value' THEN (detail->>'client_value')::numeric WHEN 'profit' THEN (detail->>'profit')::numeric WHEN 'margin' THEN (detail->>'margin')::numeric WHEN 'cost' THEN (detail->'costs'->>(p_filters->>'currency'))::numeric END END ASC NULLS LAST,
            CASE WHEN p_desc THEN CASE p_sort WHEN 'client_value' THEN (detail->>'client_value')::numeric WHEN 'profit' THEN (detail->>'profit')::numeric WHEN 'margin' THEN (detail->>'margin')::numeric WHEN 'cost' THEN (detail->'costs'->>(p_filters->>'currency'))::numeric END END DESC NULLS LAST,id) n
        FROM filtered
    ), client_summary AS (
        SELECT COALESCE(NULLIF(currency,''),'Unknown') currency,sum((row->>'client_value')::numeric) client_value,
            CASE WHEN bool_and(row->>'profit' IS NOT NULL) THEN sum((row->>'profit')::numeric) END profit,
            count(*) FILTER (WHERE row->>'profit' IS NULL) incomplete_rows,
            sum(COALESCE((row->>'estimate_count')::integer,0)) estimate_count
        FROM filtered GROUP BY 1
    ), cost_summary AS (
        SELECT c.key currency,sum(c.value::numeric) supplier_cost
        FROM filtered f CROSS JOIN LATERAL jsonb_each_text(f.row->'costs') c GROUP BY 1
    ), grouped_rows AS (
        SELECT *, COALESCE(CASE group_by
          WHEN 'client' THEN row->>'client_id' WHEN 'account' THEN row->>'account_id' WHEN 'pm' THEN row->>'pm_id'
          WHEN 'resource' THEN row->>'resource_id' WHEN 'service' THEN row->>'service'
          WHEN 'month' THEN substring(date,1,7) WHEN 'language' THEN concat_ws(' → ',row->>'source_language',row->>'target_language') END,'Unspecified') group_id,
          COALESCE(NULLIF(CASE group_by WHEN 'client' THEN client WHEN 'account' THEN account WHEN 'pm' THEN pm
            WHEN 'resource' THEN row->>'resource' WHEN 'service' THEN row->>'service' WHEN 'month' THEN substring(date,1,7)
            WHEN 'language' THEN concat_ws(' → ',row->>'source_language',row->>'target_language') END,''),'Unspecified') label
        FROM filtered WHERE group_by<>'none'
    ), group_values AS (
        SELECT group_id,label,COALESCE(NULLIF(currency,''),'Unknown') currency,count(*) row_count,
            sum((row->>'client_value')::numeric) client_value,
            CASE WHEN bool_and(row->>'profit' IS NOT NULL) THEN sum((row->>'profit')::numeric) END profit,
            count(*) FILTER(WHERE jsonb_array_length(detail->'blocking_issues')>0) issue_count,
            count(*) FILTER(WHERE COALESCE((row->>'estimate_count')::int,0)>0) estimate_count
        FROM grouped_rows GROUP BY 1,2,3
    ), group_costs AS (
        SELECT group_id,label,c.key currency,sum(c.value::numeric) supplier_cost
        FROM grouped_rows CROSS JOIN LATERAL jsonb_each_text(row->'costs') c GROUP BY 1,2,3
    ), group_result AS (
        SELECT COALESCE(v.label,c.label) label,COALESCE(v.currency,c.currency) currency,
            jsonb_build_object('id',COALESCE(v.group_id,c.group_id),'label',COALESCE(v.label,c.label),
                'currency',COALESCE(v.currency,c.currency),'row_count',COALESCE(v.row_count,0),
                'client_value',v.client_value,'supplier_cost',c.supplier_cost,'profit',v.profit,
                'margin',CASE WHEN v.client_value<>0 THEN round(v.profit/v.client_value*100,2) END,
                'issue_count',v.issue_count,'estimate_count',v.estimate_count) data
        FROM group_values v FULL JOIN group_costs c USING(group_id,label,currency)
    )
    SELECT jsonb_build_object(
        'rows',COALESCE((SELECT jsonb_agg(detail ORDER BY n) FROM ordered WHERE n>p_offset AND n<=p_offset+p_limit),'[]'::jsonb),
        'total_count',(SELECT count(*) FROM filtered),
        'project_count',(SELECT count(DISTINCT project_id) FROM filtered),
        'summary_by_currency',COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'currency',COALESCE(c.currency,k.currency),'client_value',c.client_value,'supplier_cost',k.supplier_cost,
            'profit',c.profit,'margin',CASE WHEN c.client_value<>0 THEN round(c.profit/c.client_value*100,2) END,
            'incomplete_rows',c.incomplete_rows,'estimate_count',c.estimate_count) ORDER BY COALESCE(c.currency,k.currency))
            FROM client_summary c FULL JOIN cost_summary k USING(currency)),'[]'::jsonb),
        'warning_rows',(SELECT count(*) FROM filtered WHERE jsonb_array_length(detail->'blocking_issues')>0),
        'estimate_rows',(SELECT count(*) FROM filtered WHERE COALESCE((row->>'estimate_count')::int,0)>0),
        'api_version','059',
        'groups',COALESCE((SELECT jsonb_agg(g.data ORDER BY g.label,g.currency) FROM group_result g),'[]'::jsonb),
        'filters',p_filters,'report_type',p_type,'date_basis',CASE WHEN date_basis='project' THEN 'Project date' WHEN p_type='jobs' THEN 'Job deadline (UTC)' WHEN p_type='margin' THEN 'Scoop deadline (UTC)' ELSE 'Project deadline (UTC)' END,
        'generated_at',statement_timestamp(),'next_offset',CASE WHEN p_offset+p_limit<(SELECT count(*) FROM filtered) THEN p_offset+p_limit END
    ) INTO result;
    RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.tms_report(TEXT,JSONB,INTEGER,INTEGER,TEXT,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tms_report(TEXT,JSONB,INTEGER,INTEGER,TEXT,BOOLEAN) TO authenticated;

-- Filter choices use exactly the same invoker permissions as the reports.
CREATE OR REPLACE FUNCTION public.tms_report_options_059() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public
AS $$
BEGIN
    IF NOT COALESCE(public.is_company_user(),FALSE) OR NOT COALESCE(public.current_user_access_enabled(),FALSE) THEN
        RAISE EXCEPTION 'Company report access required' USING ERRCODE='42501';
    END IF;
    RETURN jsonb_build_object('api_version','059',
      'clients',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.name,x.id) FROM (SELECT c.id,c.name FROM clients c WHERE EXISTS(SELECT 1 FROM projects p WHERE p.client_id=c.id)) x),'[]'::jsonb),
      'accounts',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.name,x.id) FROM (SELECT a.id,a.name,a.client_id FROM client_accounts a WHERE EXISTS(SELECT 1 FROM projects p WHERE p.account_id=a.id)) x),'[]'::jsonb),
      'managers',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.name,x.id) FROM (SELECT DISTINCT p.project_manager_resource_id id,COALESCE(NULLIF(r.legal_name,''),NULLIF(r.company_name,''),p.project_manager,r.internal_number) name FROM projects p JOIN resources r ON r.id=p.project_manager_resource_id) x),'[]'::jsonb),
      'resources',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.name,x.id) FROM (SELECT r.id,COALESCE(NULLIF(r.legal_name,''),NULLIF(r.company_name,''),r.internal_number) name,r.internal_number FROM resources r WHERE EXISTS(SELECT 1 FROM project_jobs j JOIN projects p ON p.id=j.project_id WHERE j.resource_id=r.id)) x),'[]'::jsonb),
      'languages',COALESCE((SELECT jsonb_agg(x.value ORDER BY x.value) FROM (SELECT source_language value FROM project_scoops UNION SELECT target_language FROM project_scoops UNION SELECT source_language FROM project_jobs UNION SELECT target_language FROM project_jobs) x WHERE NULLIF(x.value,'') IS NOT NULL),'[]'::jsonb),
      'services',COALESCE((SELECT jsonb_agg(x.value ORDER BY x.value) FROM (SELECT DISTINCT service_type value FROM project_jobs WHERE NULLIF(service_type,'') IS NOT NULL) x),'[]'::jsonb),
      'currencies',COALESCE((SELECT jsonb_agg(x.value ORDER BY x.value) FROM (SELECT currency value FROM projects UNION SELECT supplier_currency FROM project_jobs UNION SELECT currency FROM supplier_purchase_orders) x WHERE NULLIF(x.value,'') IS NOT NULL),'[]'::jsonb),
      'project_statuses',jsonb_build_array('Assign','Ongoing','Ready for QA','Waiting','Ready to Deliver','Delivered to Client','Approved','Cancelled'),
      'job_statuses',jsonb_build_array('Unassigned','Assigned','In Progress','Delivered','Revision Required','Approved','Cancelled'));
END;
$$;
REVOKE ALL ON FUNCTION public.tms_report_options_059() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tms_report_options_059() TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

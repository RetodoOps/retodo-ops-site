-- Read-only Projects, Jobs and Margin reports. Apply after migration 051.
-- Invoker rights preserve table RLS. No data or existing policy changes.
BEGIN;
CREATE OR REPLACE FUNCTION public.tms_report(
    p_type TEXT DEFAULT 'projects', p_filters JSONB DEFAULT '{}'::jsonb,
    p_offset INTEGER DEFAULT 0, p_limit INTEGER DEFAULT 50,
    p_sort TEXT DEFAULT 'name', p_desc BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = public
AS $$
DECLARE result JSONB; from_date DATE; to_date DATE; scope TEXT;
BEGIN
    IF NOT COALESCE(public.is_company_user(), FALSE)
       OR NOT COALESCE(public.current_user_access_enabled(), FALSE) THEN
        RAISE EXCEPTION 'Company report access required' USING ERRCODE = '42501';
    END IF;
    IF p_type IS NULL OR p_type NOT IN ('projects','jobs','margin')
       OR p_sort IS NULL OR p_sort NOT IN ('name','date','status','client')
       OR p_offset IS NULL OR p_offset < 0 OR p_limit IS NULL OR p_limit < 1 OR p_limit > 10000
       OR p_desc IS NULL OR p_filters IS NULL OR jsonb_typeof(p_filters) <> 'object' THEN
        RAISE EXCEPTION 'Invalid report parameters';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_filters) k
               WHERE k NOT IN ('search','client','account','pm','status','from','to','scope')) THEN
        RAISE EXCEPTION 'Unsupported report filter';
    END IF;
    from_date := NULLIF(p_filters->>'from','')::date;
    to_date := NULLIF(p_filters->>'to','')::date;
    scope := COALESCE(p_filters->>'scope','active');
    IF scope NOT IN ('active','all') OR from_date > to_date THEN
        RAISE EXCEPTION 'Invalid scope or date range';
    END IF;

    WITH project_base AS MATERIALIZED (
        SELECT p.id, p.project_number, COALESCE(NULLIF(p.display_name,''),p.project_number) name,
            p.project_date, p.deadline, p.status, p.currency, p.project_manager pm,
            c.name client, a.name account
        FROM public.projects p
        LEFT JOIN public.clients c ON c.id = p.client_id
        LEFT JOIN public.client_accounts a ON a.id = p.account_id
        WHERE (scope = 'all' OR p.status <> 'Cancelled')
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
            s.price client_value, s.deadline, p.currency,
            (SELECT count(*) FROM job_base j WHERE j.project_scoop_id=s.id) job_count,
            (SELECT count(*) FROM public.project_jobs j WHERE j.project_scoop_id=s.id AND j.status IN ('Cancelled','Declined')) excluded_job_count,
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
            (SELECT count(*) FROM job_base j WHERE j.project_id=p.id) job_count,
            (SELECT count(*) FROM public.project_jobs j WHERE j.project_id=p.id AND j.status IN ('Cancelled','Declined')) excluded_job_count,
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
            p.project_date::text date,p.currency,
            to_jsonb(p) - 'numeric_cost' || jsonb_build_object('project_id',p.id,'date',p.project_date,
                'profit',CASE WHEN p.scoop_count>0 AND p.job_count>0 AND p.unknown_cost_count=0 AND p.po_warning_count=0 AND p.currency_warning_count=0 AND p.unallocated_job_count=0 AND NULLIF(p.currency,'') IS NOT NULL THEN p.client_value-p.numeric_cost END) row
        FROM project_metrics p WHERE p_type='projects'
        UNION ALL
        SELECT s.id,p.id,s.name,s.status,p.client,p.account,p.pm,p.project_date::text,p.currency,
            to_jsonb(s) - 'numeric_cost' || jsonb_build_object('project_id',p.id,'project_name',p.name,'client',p.client,'account',p.account,'pm',p.pm,'date',p.project_date,
                'profit',CASE WHEN s.job_count>0 AND s.unknown_cost_count=0 AND s.po_warning_count=0 AND s.currency_warning_count=0 AND NULLIF(p.currency,'') IS NOT NULL THEN s.client_value-s.numeric_cost END)
        FROM scoop_metrics s JOIN project_base p ON p.id=s.project_id WHERE p_type='margin'
        UNION ALL
        SELECT j.id,p.id,j.job_number,j.status,p.client,p.account,p.pm,
            (j.deadline AT TIME ZONE 'UTC')::date::text,j.cost_currency,
            jsonb_build_object('id',j.id,'project_id',p.id,'project_name',p.name,'scoop_id',j.project_scoop_id,
                'name',j.job_number,'status',j.status,'client',p.client,'account',p.account,'pm',p.pm,
                'date',(j.deadline AT TIME ZONE 'UTC')::date,'deadline',j.deadline,
                'service',j.service_type,'source_language',j.source_language,'target_language',j.target_language,
                'resource',j.resource_name,'quantity',j.quantity,'unit',j.unit,
                'costs',jsonb_build_object(COALESCE(NULLIF(j.cost_currency,''),'Unknown'),j.cost),
                'currency',j.cost_currency,'cost_basis',j.cost_basis,'po_id',j.po_id,'po_number',j.po_number,'po_version',j.po_version,
                'active_po_count',j.active_po_count,'estimate_count',CASE WHEN j.cost_basis='Estimate' THEN 1 ELSE 0 END,
                'unknown_cost_count',CASE WHEN j.cost IS NULL THEN 1 ELSE 0 END,
                'po_warning_count',CASE WHEN j.po_warning OR j.active_po_count>1 THEN 1 ELSE 0 END,
                'currency_warning_count',CASE WHEN NULLIF(j.cost_currency,'') IS NULL THEN 1 ELSE 0 END)
        FROM job_base j JOIN project_base p ON p.id=j.project_id WHERE p_type='jobs'
    ), filtered AS MATERIALIZED (
        SELECT *, row || jsonb_build_object('margin',CASE WHEN (row->>'client_value')::numeric <> 0
                THEN round((row->>'profit')::numeric / (row->>'client_value')::numeric * 100,2) END) detail
        FROM raw_rows r
        WHERE (COALESCE(p_filters->>'status','')='' OR r.status=p_filters->>'status')
          AND (from_date IS NULL OR r.date::date>=from_date)
          AND (to_date IS NULL OR r.date::date<=to_date)
          AND (COALESCE(p_filters->>'search','')='' OR
               concat_ws(' ',r.name,r.client,r.account,r.pm,r.row->>'resource',r.row->>'service',r.row->>'project_name',r.row->>'source_language',r.row->>'target_language') ILIKE '%' || (p_filters->>'search') || '%')
    ), ordered AS (
        SELECT *,row_number() OVER (ORDER BY
            CASE WHEN NOT p_desc THEN CASE p_sort WHEN 'name' THEN name WHEN 'date' THEN date WHEN 'status' THEN status WHEN 'client' THEN client END END ASC NULLS LAST,
            CASE WHEN p_desc THEN CASE p_sort WHEN 'name' THEN name WHEN 'date' THEN date WHEN 'status' THEN status WHEN 'client' THEN client END END DESC NULLS LAST,id) n
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
        'warning_rows',(SELECT count(*) FROM filtered WHERE COALESCE((row->>'unknown_cost_count')::int,0)>0 OR COALESCE((row->>'po_warning_count')::int,0)>0 OR COALESCE((row->>'currency_warning_count')::int,0)>0 OR (p_type<>'jobs' AND row->>'profit' IS NULL)),
        'filters',p_filters,'report_type',p_type,'date_basis',CASE WHEN p_type='jobs' THEN 'Job deadline (UTC)' ELSE 'Project date' END,
        'generated_at',statement_timestamp(),'next_offset',CASE WHEN p_offset+p_limit<(SELECT count(*) FROM filtered) THEN p_offset+p_limit END
    ) INTO result;
    RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.tms_report(TEXT,JSONB,INTEGER,INTEGER,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tms_report(TEXT,JSONB,INTEGER,INTEGER,TEXT,BOOLEAN) TO authenticated;
COMMIT;

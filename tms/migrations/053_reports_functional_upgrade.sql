-- Update 059. Apply after 052. Forward-only Reports upgrade; no base-table writes.
-- Invoker rights preserve table RLS. No data or existing policy changes.
BEGIN;
CREATE OR REPLACE FUNCTION public.tms_report(
    p_type TEXT DEFAULT 'projects', p_filters JSONB DEFAULT '{}'::jsonb,
    p_offset INTEGER DEFAULT 0, p_limit INTEGER DEFAULT 50,
    p_sort TEXT DEFAULT 'name', p_desc BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = public
AS $$
DECLARE result JSONB; from_date DATE; to_date DATE; scope TEXT; date_basis TEXT; group_by TEXT;
BEGIN
    IF NOT COALESCE(public.is_company_user(), FALSE)
       OR NOT COALESCE(public.current_user_access_enabled(), FALSE) THEN
        RAISE EXCEPTION 'Company report access required' USING ERRCODE = '42501';
    END IF;
    IF p_type IS NULL OR p_type NOT IN ('projects','jobs','margin')
       OR p_sort IS NULL OR p_sort NOT IN ('name','date','status','client','cost','profit','margin','client_value')
       OR p_offset IS NULL OR p_offset < 0 OR p_limit IS NULL OR p_limit < 1 OR p_limit > 10000
       OR p_desc IS NULL OR p_filters IS NULL OR jsonb_typeof(p_filters) <> 'object' THEN
        RAISE EXCEPTION 'Invalid report parameters';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_filters) k
               WHERE k NOT IN ('search','client','account','pm','status','from','to','scope','client_id','account_id','pm_id','resource_id','source_language','target_language','service','currency','statuses','cost_basis','quality','margin_min','margin_max','date_basis','group_by')) THEN
        RAISE EXCEPTION 'Unsupported report filter';
    END IF;
    from_date := NULLIF(p_filters->>'from','')::date;
    to_date := NULLIF(p_filters->>'to','')::date;
    scope := COALESCE(p_filters->>'scope','active');
    IF scope NOT IN ('active','all') OR from_date > to_date THEN
        RAISE EXCEPTION 'Invalid scope or date range';
    END IF;

    date_basis := COALESCE(NULLIF(p_filters->>'date_basis',''),CASE WHEN p_type='jobs' THEN 'deadline' ELSE 'project_date' END);
    group_by := COALESCE(NULLIF(p_filters->>'group_by',''),'none');
    IF date_basis NOT IN ('project_date','deadline') OR group_by NOT IN ('none','client','account','pm','resource','month')
       OR (group_by='resource' AND p_type<>'jobs') THEN RAISE EXCEPTION 'Unsupported date basis or grouping'; END IF;
    IF p_sort IN ('cost','profit','margin','client_value') AND NULLIF(p_filters->>'currency','') IS NULL THEN
        RAISE EXCEPTION 'Choose a currency before financial sorting';
    END IF;
    IF p_type='jobs' AND (p_sort IN ('profit','margin','client_value') OR NULLIF(p_filters->>'margin_min','') IS NOT NULL OR NULLIF(p_filters->>'margin_max','') IS NOT NULL) THEN
        RAISE EXCEPTION 'Jobs have no allocated client value or margin';
    END IF;
    IF NULLIF(p_filters->>'margin_min','')::numeric > NULLIF(p_filters->>'margin_max','')::numeric THEN RAISE EXCEPTION 'Invalid margin range'; END IF;
    IF p_filters ? 'statuses' AND jsonb_typeof(p_filters->'statuses') <> 'array' THEN RAISE EXCEPTION 'Statuses must be an array'; END IF;
    IF COALESCE(p_filters->>'quality','') NOT IN ('','blocking','estimate','unknown_cost','po_conflict','currency_mismatch','excluded','clean')
       OR COALESCE(p_filters->>'cost_basis','') NOT IN ('','PO commitment','Estimate','Unknown') THEN RAISE EXCEPTION 'Unsupported quality or cost basis'; END IF;

    WITH project_base AS MATERIALIZED (
        SELECT p.id, p.project_number, COALESCE(NULLIF(p.display_name,''),p.project_number) name,
            p.project_date, p.deadline, p.status, p.currency, p.project_manager pm,
            c.name client, a.name account, p.client_id, p.account_id, p.project_manager_resource_id pm_id
        FROM public.projects p
        LEFT JOIN public.clients c ON c.id = p.client_id
        LEFT JOIN public.client_accounts a ON a.id = p.account_id
        WHERE (scope = 'all' OR p.status <> 'Cancelled')
          AND (COALESCE(p_filters->>'client','') = '' OR c.name ILIKE '%' || (p_filters->>'client') || '%')
          AND (COALESCE(p_filters->>'account','') = '' OR a.name ILIKE '%' || (p_filters->>'account') || '%')
          AND (COALESCE(p_filters->>'pm','') = '' OR p.project_manager = p_filters->>'pm')
          AND (NULLIF(p_filters->>'client_id','') IS NULL OR p.client_id=NULLIF(p_filters->>'client_id','')::uuid)
          AND (NULLIF(p_filters->>'account_id','') IS NULL OR p.account_id=NULLIF(p_filters->>'account_id','')::uuid)
          AND (NULLIF(p_filters->>'pm_id','') IS NULL OR p.project_manager_resource_id=NULLIF(p_filters->>'pm_id','')::uuid)
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
            CASE WHEN date_basis='deadline' THEN (p.deadline AT TIME ZONE 'UTC')::date ELSE p.project_date END::text date,p.currency,
            to_jsonb(p) - 'numeric_cost' || jsonb_build_object('project_id',p.id,'date',CASE WHEN date_basis='deadline' THEN (p.deadline AT TIME ZONE 'UTC')::date ELSE p.project_date END,
                'profit',CASE WHEN p.scoop_count>0 AND p.empty_scoop_count=0 AND p.job_count>0 AND p.unknown_cost_count=0 AND p.po_warning_count=0 AND p.currency_warning_count=0 AND p.unallocated_job_count=0 AND NULLIF(p.currency,'') IS NOT NULL THEN p.client_value-p.numeric_cost END) row
        FROM project_metrics p WHERE p_type='projects'
        UNION ALL
        SELECT s.id,p.id,s.name,s.status,p.client,p.account,p.pm,CASE WHEN date_basis='deadline' THEN (s.deadline AT TIME ZONE 'UTC')::date ELSE p.project_date END::text,p.currency,
            to_jsonb(s) - 'numeric_cost' || jsonb_build_object('project_id',p.id,'project_name',p.name,'project_number',p.project_number,'client_id',p.client_id,'account_id',p.account_id,'pm_id',p.pm_id,'client',p.client,'account',p.account,'pm',p.pm,'date',CASE WHEN date_basis='deadline' THEN (s.deadline AT TIME ZONE 'UTC')::date ELSE p.project_date END,
                'profit',CASE WHEN s.job_count>0 AND s.unallocated_job_count=0 AND s.unknown_cost_count=0 AND s.po_warning_count=0 AND s.currency_warning_count=0 AND NULLIF(p.currency,'') IS NOT NULL THEN s.client_value-s.numeric_cost END)
        FROM scoop_metrics s JOIN project_base p ON p.id=s.project_id WHERE p_type='margin'
        UNION ALL
        SELECT j.id,p.id,j.job_number,j.status,p.client,p.account,p.pm,
            CASE WHEN date_basis='project_date' THEN p.project_date ELSE (j.deadline AT TIME ZONE 'UTC')::date END::text,j.cost_currency,
            jsonb_build_object('id',j.id,'project_id',p.id,'project_name',p.name,'project_number',p.project_number,'client_id',p.client_id,'account_id',p.account_id,'pm_id',p.pm_id,'scoop_id',j.project_scoop_id,'scoop_number',(SELECT s.scoop_number FROM scoop_base s WHERE s.id=j.project_scoop_id),'resource_id',j.resource_id,
                'name',j.job_number,'status',j.status,'client',p.client,'account',p.account,'pm',p.pm,
                'date',CASE WHEN date_basis='project_date' THEN p.project_date ELSE (j.deadline AT TIME ZONE 'UTC')::date END,'deadline',j.deadline,
                'service',j.service_type,'source_language',j.source_language,'target_language',j.target_language,
                'resource',j.resource_name,'quantity',j.quantity,'unit',j.unit,
                'costs',jsonb_build_object(COALESCE(NULLIF(j.cost_currency,''),'Unknown'),j.cost),
                'currency',j.cost_currency,'cost_basis',j.cost_basis,'po_id',j.po_id,'po_number',j.po_number,'po_version',j.po_version,
                'active_po_count',j.active_po_count,'estimate_count',CASE WHEN j.cost_basis='Estimate' THEN 1 ELSE 0 END,
                'unknown_cost_count',CASE WHEN j.cost IS NULL THEN 1 ELSE 0 END,
                'po_warning_count',CASE WHEN j.po_warning OR j.active_po_count>1 THEN 1 ELSE 0 END,
                'currency_warning_count',CASE WHEN NULLIF(j.cost_currency,'') IS NULL THEN 1 ELSE 0 END)
        FROM job_base j JOIN project_base p ON p.id=j.project_id WHERE p_type='jobs'
    ), decorated AS (
        SELECT *, row || jsonb_build_object(
            'margin',CASE WHEN (row->>'client_value')::numeric<>0 THEN round((row->>'profit')::numeric/(row->>'client_value')::numeric*100,2) END,
            'issue_codes',to_jsonb(array_remove(ARRAY[
                CASE WHEN COALESCE((row->>'unknown_cost_count')::int,0)>0 THEN 'unknown_cost' END,
                CASE WHEN COALESCE((row->>'po_warning_count')::int,0)>0 THEN 'po_conflict' END,
                CASE WHEN COALESCE((row->>'currency_warning_count')::int,0)>0 THEN 'currency_mismatch' END,
                CASE WHEN p_type<>'jobs' AND row->>'profit' IS NULL THEN 'incomplete_margin' END
            ],NULL)),
            'info_codes',to_jsonb(array_remove(ARRAY[
                CASE WHEN COALESCE((row->>'estimate_count')::int,0)>0 THEN 'estimate' END,
                CASE WHEN COALESCE((row->>'excluded_job_count')::int,0)>0 THEN 'excluded' END
            ],NULL))) detail
        FROM raw_rows
    ), matched AS (
        SELECT * FROM decorated r
        WHERE (COALESCE(p_filters->>'status','')='' OR r.status=p_filters->>'status')
          AND (COALESCE(p_filters->'statuses','[]'::jsonb)='[]'::jsonb OR (p_filters->'statuses') ? r.status)
          AND (from_date IS NULL OR r.date::date>=from_date) AND (to_date IS NULL OR r.date::date<=to_date)
          AND (COALESCE(p_filters->>'currency','')='' OR r.currency=p_filters->>'currency')
          AND (NULLIF(p_filters->>'margin_min','') IS NULL OR (detail->>'margin')::numeric >= (p_filters->>'margin_min')::numeric)
          AND (NULLIF(p_filters->>'margin_max','') IS NULL OR (detail->>'margin')::numeric <= (p_filters->>'margin_max')::numeric)
          AND (COALESCE(p_filters->>'search','')='' OR
              concat_ws(' ',r.name,r.row->>'project_number',r.client,r.account,r.pm,r.row->>'resource',r.row->>'service',r.row->>'project_name',r.row->>'source_language',r.row->>'target_language') ILIKE '%'||(p_filters->>'search')||'%'
              OR (p_type<>'jobs' AND EXISTS (SELECT 1 FROM job_base j WHERE j.project_id=r.project_id AND (p_type='projects' OR j.project_scoop_id=r.id)
                  AND concat_ws(' ',j.job_number,j.resource_name,j.service_type,j.source_language,j.target_language) ILIKE '%'||(p_filters->>'search')||'%'))
              OR (p_type='projects' AND EXISTS (SELECT 1 FROM scoop_base s WHERE s.project_id=r.project_id AND concat_ws(' ',s.scoop_number,s.source_language,s.target_language) ILIKE '%'||(p_filters->>'search')||'%')))
          -- Relationship filters select whole Projects/Scoops; they never trim their financial totals.
          AND ( (COALESCE(p_filters->>'resource_id','')='' AND COALESCE(p_filters->>'service','')='' AND COALESCE(p_filters->>'cost_basis','')=''
                 AND COALESCE(p_filters->>'source_language','')='' AND COALESCE(p_filters->>'target_language','')='')
            OR EXISTS (SELECT 1 FROM job_base j WHERE j.project_id=r.project_id
                AND (p_type='projects' OR (p_type='margin' AND j.project_scoop_id=r.id) OR (p_type='jobs' AND j.id=r.id))
                AND (NULLIF(p_filters->>'resource_id','') IS NULL OR j.resource_id=NULLIF(p_filters->>'resource_id','')::uuid)
                AND (COALESCE(p_filters->>'service','')='' OR j.service_type=p_filters->>'service')
                AND (COALESCE(p_filters->>'cost_basis','')='' OR j.cost_basis=p_filters->>'cost_basis')
                AND (COALESCE(p_filters->>'source_language','')='' OR j.source_language=p_filters->>'source_language')
                AND (COALESCE(p_filters->>'target_language','')='' OR j.target_language=p_filters->>'target_language'))
            OR (p_type<>'jobs' AND COALESCE(p_filters->>'resource_id','')='' AND COALESCE(p_filters->>'service','')='' AND COALESCE(p_filters->>'cost_basis','')=''
                AND EXISTS (SELECT 1 FROM scoop_base s WHERE s.project_id=r.project_id AND (p_type='projects' OR s.id=r.id)
                    AND (COALESCE(p_filters->>'source_language','')='' OR s.source_language=p_filters->>'source_language')
                    AND (COALESCE(p_filters->>'target_language','')='' OR s.target_language=p_filters->>'target_language'))))
    ), filtered AS MATERIALIZED (
        SELECT * FROM matched WHERE COALESCE(p_filters->>'quality','')=''
            OR (p_filters->>'quality'='blocking' AND jsonb_array_length(detail->'issue_codes')>0)
            OR (p_filters->>'quality'='clean' AND jsonb_array_length(detail->'issue_codes')=0)
            OR (detail->'issue_codes') ? (p_filters->>'quality') OR (detail->'info_codes') ? (p_filters->>'quality')
    ), ordered AS (
        SELECT *,row_number() OVER (ORDER BY
            CASE WHEN NOT p_desc THEN CASE p_sort WHEN 'cost' THEN (row->'costs'->>(p_filters->>'currency'))::numeric WHEN 'profit' THEN (row->>'profit')::numeric WHEN 'margin' THEN (detail->>'margin')::numeric WHEN 'client_value' THEN (row->>'client_value')::numeric END END ASC NULLS LAST,
            CASE WHEN p_desc THEN CASE p_sort WHEN 'cost' THEN (row->'costs'->>(p_filters->>'currency'))::numeric WHEN 'profit' THEN (row->>'profit')::numeric WHEN 'margin' THEN (detail->>'margin')::numeric WHEN 'client_value' THEN (row->>'client_value')::numeric END END DESC NULLS LAST,
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
    ), group_rows AS (
        SELECT *, CASE group_by WHEN 'client' THEN COALESCE(row->>'client_id','unassigned') WHEN 'account' THEN COALESCE(row->>'account_id','unassigned') WHEN 'pm' THEN COALESCE(row->>'pm_id','legacy:'||pm,'unassigned') WHEN 'resource' THEN COALESCE(row->>'resource_id','unassigned') WHEN 'month' THEN COALESCE(to_char(date::date,'YYYY-MM'),'No date') END group_id,
          CASE group_by WHEN 'client' THEN client WHEN 'account' THEN account WHEN 'pm' THEN pm WHEN 'resource' THEN row->>'resource' WHEN 'month' THEN to_char(date::date,'YYYY-MM') END group_label
        FROM filtered WHERE group_by<>'none'
    ), grouped AS (
        SELECT group_id,min(group_label) group_label,COALESCE(NULLIF(currency,''),'Unknown') currency,count(*) row_count,
            sum((row->>'client_value')::numeric) client_value,
            CASE WHEN bool_and(row->>'profit' IS NOT NULL) THEN sum((row->>'profit')::numeric) END profit,
            count(*) FILTER(WHERE jsonb_array_length(detail->'issue_codes')>0) issue_rows
        FROM group_rows GROUP BY 1,3
    ), group_costs AS (
        SELECT group_id,min(group_label) group_label,c.key currency,sum(c.value::numeric) supplier_cost
        FROM group_rows CROSS JOIN LATERAL jsonb_each_text(row->'costs') c GROUP BY 1,3
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
        'warning_rows',(SELECT count(*) FROM filtered WHERE jsonb_array_length(detail->'issue_codes')>0),
        'issue_counts',(SELECT jsonb_build_object('blocking',count(*) FILTER(WHERE jsonb_array_length(detail->'issue_codes')>0),
            'unknown_cost',count(*) FILTER(WHERE (detail->'issue_codes') ? 'unknown_cost'),
            'po_conflict',count(*) FILTER(WHERE (detail->'issue_codes') ? 'po_conflict'),
            'currency_mismatch',count(*) FILTER(WHERE (detail->'issue_codes') ? 'currency_mismatch'),
            'estimate',count(*) FILTER(WHERE (detail->'info_codes') ? 'estimate'),
            'excluded',count(*) FILTER(WHERE (detail->'info_codes') ? 'excluded')) FROM filtered),
        'groups',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',COALESCE(g.group_id,k.group_id),'label',COALESCE(g.group_label,k.group_label,'Unassigned'),
            'currency',COALESCE(g.currency,k.currency),'row_count',g.row_count,'client_value',g.client_value,'supplier_cost',k.supplier_cost,'profit',g.profit,
            'margin',CASE WHEN g.client_value<>0 THEN round(g.profit/g.client_value*100,2) END,'issue_rows',g.issue_rows) ORDER BY COALESCE(g.group_label,k.group_label),COALESCE(g.group_id,k.group_id),COALESCE(g.currency,k.currency))
            FROM grouped g FULL JOIN group_costs k ON g.group_id=k.group_id AND g.currency=k.currency),'[]'::jsonb),
        'filters',p_filters,'report_type',p_type,'api_version',59,'date_basis',CASE WHEN date_basis='project_date' THEN 'Project date' WHEN p_type='jobs' THEN 'Job deadline (UTC)' WHEN p_type='margin' THEN 'Scoop deadline (UTC)' ELSE 'Project deadline (UTC)' END,
        'generated_at',statement_timestamp(),'next_offset',CASE WHEN p_offset+p_limit<(SELECT count(*) FROM filtered) THEN p_offset+p_limit END
    ) INTO result;
    RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.tms_report(TEXT,JSONB,INTEGER,INTEGER,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tms_report(TEXT,JSONB,INTEGER,INTEGER,TEXT,BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.tms_report_options() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public AS $$
DECLARE result jsonb;
BEGIN
 IF NOT COALESCE(public.is_company_user(),false) OR NOT COALESCE(public.current_user_access_enabled(),false) THEN
    RAISE EXCEPTION 'Company report access required' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object('api_version',59,
 'clients',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'label',c.name) ORDER BY c.name,c.id) FROM public.clients c),'[]'::jsonb),
 'accounts',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',a.id,'client_id',a.client_id,'label',a.name) ORDER BY a.name,a.id) FROM public.client_accounts a),'[]'::jsonb),
 'pms',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',x.id,'label',x.label) ORDER BY x.label,x.id) FROM (SELECT p.project_manager_resource_id id,min(p.project_manager) label FROM public.projects p WHERE p.project_manager_resource_id IS NOT NULL GROUP BY p.project_manager_resource_id) x),'[]'::jsonb),
 'legacy_pms',COALESCE((SELECT jsonb_agg(x.pm ORDER BY x.pm) FROM (SELECT DISTINCT project_manager pm FROM public.projects WHERE project_manager_resource_id IS NULL AND NULLIF(project_manager,'') IS NOT NULL) x),'[]'::jsonb),
 'resources',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'label',concat_ws(' · ',r.internal_number,COALESCE(NULLIF(r.legal_name,''),r.company_name))) ORDER BY r.internal_number,r.id) FROM public.resources r WHERE EXISTS(SELECT 1 FROM public.project_jobs j WHERE j.resource_id=r.id)),'[]'::jsonb),
 'languages',COALESCE((SELECT jsonb_agg(v ORDER BY v) FROM (SELECT source_language v FROM public.project_jobs UNION SELECT target_language FROM public.project_jobs UNION SELECT source_language FROM public.project_scoops UNION SELECT target_language FROM public.project_scoops) x WHERE NULLIF(v,'') IS NOT NULL),'[]'::jsonb),
 'services',COALESCE((SELECT jsonb_agg(v ORDER BY v) FROM (SELECT DISTINCT service_type v FROM public.project_jobs) x WHERE NULLIF(v,'') IS NOT NULL),'[]'::jsonb),
 'currencies',COALESCE((SELECT jsonb_agg(v ORDER BY v) FROM (SELECT currency v FROM public.projects UNION SELECT supplier_currency FROM public.project_jobs UNION SELECT currency FROM public.supplier_purchase_orders) x WHERE NULLIF(v,'') IS NOT NULL),'[]'::jsonb),
 'statuses',COALESCE((SELECT jsonb_object_agg(entity,values) FROM (
     SELECT CASE conrelid WHEN 'public.projects'::regclass THEN 'projects' WHEN 'public.project_jobs'::regclass THEN 'jobs' ELSE 'margin' END entity,
         (SELECT jsonb_agg(m[1]) FROM regexp_matches(pg_get_constraintdef(c.oid),$re$'([^']+)'$re$,'g') m) values
     FROM pg_constraint c WHERE conname IN ('projects_new_status_check','project_jobs_status_check','project_scoops_status_check')
       AND conrelid IN ('public.projects'::regclass,'public.project_jobs'::regclass,'public.project_scoops'::regclass)
 ) x),'{}'::jsonb)) INTO result;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.tms_report_options() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tms_report_options() TO authenticated;
COMMIT;

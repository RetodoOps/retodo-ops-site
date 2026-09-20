# Retodo Ops — Secret Reference Policy

**Never store real secret values in this repository.**

The broader Retodo Ops project may track which systems/accounts exist, but Git/context files must contain only references.

---

## 1. Never commit

Do not commit or paste:

- passwords;
- recovery codes;
- MFA seeds;
- Supabase service-role keys;
- private API keys;
- OAuth client secrets;
- Gmail refresh tokens;
- R2 secret access keys;
- Resend/provider API keys;
- Netlify personal tokens;
- database passwords;
- private signing keys.

---

## 2. Allowed registry format

Use references such as:

| System | Purpose | Account/owner | Secret location | Env variable(s) | Last verified |
|---|---|---|---|---|---|
| Supabase | TMS DB/Auth | Retodo Ops | Password manager: `Retodo/TMS/Supabase Production` | `NEXT_PUBLIC_SUPABASE_URL`, `...` | YYYY-MM-DD |
| Cloudflare R2 | TMS files | Retodo Ops | Password manager: `Retodo/TMS/R2` | `R2_*` | YYYY-MM-DD |
| Email provider | transactional email | Retodo Ops | Password manager reference | provider-specific | YYYY-MM-DD |

Do not fill `Secret location` with the secret itself.

---

## 3. If a secret is exposed

1. Do not copy it into context docs.
2. Redact it from reports.
3. Rotate/revoke it at the provider.
4. Update environment variables.
5. Note only that rotation occurred and where the new secret is stored.


## Public-repository warning

`RetodoOps/retodo-ops-site` is public. Therefore the private daily `Retodo_Ops_Master_Context_and_Decisions.md` must not be committed there. Only repo-safe distilled rules belong under `docs/context/`.

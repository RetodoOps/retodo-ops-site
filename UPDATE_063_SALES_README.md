# Retodo Ops — Update 063 Sales

This is a complete-file update for the installed Update 062 TMS. Upload each file to the same repository path after following the installation guide.

1. Confirm migration 056 is installed.
2. Run `tms/migrations/057_sales_workspace.sql` in Supabase.
3. Run `tms/audits/017_update_063_sales_audit.sql`; all 31 checks must pass.
4. Upload/commit the complete package files, including root `netlify.toml` and `netlify/functions/`.
5. Follow `docs/sales/UPDATE_063_INSTALL_AND_TEST.md` for environment variables, mailbox verification and the controlled pilot.

Sales includes prospects and contact research, LinkedIn suggestions, pitch drafting, batch approval, email sequences, replies, materials/PowerPoint export and Client conversion. AI and mail automation require the configuration in the guide.

Sending and scheduled research start **off**. The monthly application ceiling is **€30**. Every Sales email uses Eli Stoyanova `<eli.s@retodo-ops.com>` for From and Reply-To. General Gmail sender settings and the existing operational mail helper are preserved.

No production migration, deployment, live email or paid AI request was performed during development.

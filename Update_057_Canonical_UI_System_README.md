# Retodo Ops TMS — Update 057

## Purpose

This release replaces the partial visual overrides from Update 056 with a canonical layout and component system across all 17 TMS screens.

## Included

- Shared spacing scale and alignment axis for page headers, toolbars, cards, tables and forms.
- Clear H1, H2, module, sub-module, label and supporting-text hierarchy.
- Standardized primary, secondary, tertiary and destructive action geometry.
- Help text moved into accessible hover/focus tooltips beside the relevant heading or label.
- Consistent record-row and evidence-file sizing.
- Normalized Compliance and Qualifications section spacing.
- Purple upload controls and prominent operational actions.
- Responsive rules for narrow screens.
- Shared cache key `057` for `style.css` and `auth.js` on all TMS screens.

## Deployment

Upload the package contents to the repository root and replace the included files in full.

No database migration, audit SQL or new environment variable is required.

After deployment, verify `/build.json` reports `057`, hard-refresh the browser, and inspect Dashboard, Project, Job, Resource, Compliance and Resource Portal at desktop and narrow widths.

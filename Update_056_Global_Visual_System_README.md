# Retodo Ops TMS — Update 056

## Scope

This is a global interface refresh for every TMS screen, including the internal application, Resource Portal, sign-in, registration and password setup pages. It does not change business workflows or database data.

## Visual system

- Darker, clearly bounded backgrounds for editable fields.
- Consistent H1, H2, module, submodule, label and supporting-copy hierarchy.
- Shared card geometry, spacing, borders and restrained shadows.
- Compact status and date bubbles.
- More prominent Open, Download, View, Print and Export actions.
- Purple Upload actions throughout the application.
- Supporting field explanations moved into accessible `?` tooltips shown on mouse hover or keyboard focus.
- Responsive behavior retained for narrower screens.

## Session safety

If another login replaces the active Supabase session in the same browser profile, a stale TMS tab is redirected to the workspace that matches the active role. This prevents a visually cached Admin screen from producing misleading RLS errors after a Resource login.

Separate browser profiles or an Incognito window remain the recommended way to test Admin and Resource simultaneously.

## Deployment

1. Upload the complete files from this package to their matching repository paths.
2. Publish through GitHub / Netlify.
3. Verify `/build.json` reports build `056`.

There is no migration, database audit or new environment variable.

## Acceptance test

Open Dashboard, one Project, one Job, one Resource and the Resource Portal after a hard refresh. Confirm:

- field surfaces are darker and aligned;
- title hierarchy is consistent;
- date/status bubbles are compact;
- Open/Download/View actions are visually prominent;
- Upload actions are purple;
- `?` help appears on hover and keyboard focus;
- changing the active login in the same browser no longer leaves a writable stale-role screen.


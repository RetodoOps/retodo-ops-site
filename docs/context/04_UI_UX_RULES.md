# Retodo Ops TMS — UI/UX Rules

**Version:** 1.2  
**Date:** 2026-09-19

These rules exist because the user explicitly does not want to identify every spacing, alignment, text-containment or consistency defect after each UI update.

**Current source baseline:** Update 056 implements a global visual system across internal TMS, Resource Portal and auth screens. These rules are the acceptance criteria for that source; source presence alone is not visual acceptance.

---

## 1. Core principle

When touching a screen, evaluate the entire affected surface, not only the single reported defect.

A screen is not complete if individual requested controls work but the overall page is visually inconsistent, cramped, misaligned, low-contrast, or difficult to scan.

---

## 2. Hierarchy

Use a clear hierarchy:

1. Page title
2. Section heading
3. Card/group heading
4. Field label
5. Field value/input
6. Helper/explanatory text
7. Metadata

Do not make important section labels look like helper text.

For resource profile screens, `Tests & Qualifications`, `Compliance`, `Account Qualifications` and equivalent module headings must have consistent hierarchy and alignment.

---

## 3. Alignment

Use one intentional grid.

- Section titles align with their section content.
- Cards in the same row align at top and baseline where practical.
- Buttons belonging to the same action row share vertical alignment.
- `Save changes` must not visually float relative to actions such as `Assign Test`.
- Help/question icons remain inline next to the heading/label they explain, not on a separate line below it.
- Comparable evidence cards such as “Master's degree” and “Diploma upload” should use compatible dimensions/padding.

Do not rely on random per-component margins to achieve alignment.

---

## 4. Spacing system

Prefer a consistent 4/8 px rhythm.

Typical spacing:
- 4 px: icon-to-label/detail
- 8 px: tight related items
- 12–16 px: field/internal card spacing
- 20–24 px: groups
- 32 px+: major section separation

Avoid large unexplained whitespace in one module and compressed layout in the next.

---

## 5. Typography

Minimum guidance unless an existing design system already sets stronger tokens:

- normal body/input text: ~14–16 px;
- helper text: generally not below ~12–13 px;
- section headings: visibly larger/heavier than field labels;
- metadata can be smaller but must remain readable.

The text above the current test card/test identity must not be so small that it reads as accidental metadata.

Use consistent font weight and line-height for equivalent roles.

---

## 6. Contrast and surfaces

The user explicitly requested darker/clearer field backgrounds.

- Inputs/read-only fields must be visually distinguishable from page background.
- Maintain sufficient text/background contrast.
- Disabled/read-only state must still be readable.
- Avoid light gray text on near-white surfaces.
- Do not solve grouping only by borders; spacing + surface + heading hierarchy should work together.

Aim for WCAG AA contrast where practical.

---

## 7. Text containment

All explanatory/helper text must remain inside the visual container it describes.

Examples of text that must not spill outside bubbles/cards:
- “The Resource may edit and resubmit the requested Compliance changes.”
- signing-flow explanation;
- experience-duration explanation.

Rules:
- allow wrapping;
- use sane max widths;
- avoid fixed heights that clip or overflow text;
- provide padding on all sides;
- test at common desktop widths and narrower responsive widths.

---

## 8. Buttons

Use a small, consistent action hierarchy.

Recommended roles:
- Primary: main commit/submit action.
- Secondary: supporting action.
- Tertiary/ghost: navigation/light action.
- Destructive: delete/cancel destructive operation.

Equivalent buttons must have consistent:
- height;
- radius;
- font size/weight;
- padding;
- icon alignment;
- color semantics.

Do not mix multiple unrelated button styles for similar actions on the same page.

---

## 9. Forms

- Labels remain close to their control.
- Required/optional meaning is consistent.
- Read-only calculated fields look read-only but readable.
- `MM/YYYY` source fields and calculated experience must be visually distinguished.
- Validation appears next to the field and does not shift entire layout unpredictably.
- Upload controls align with neighboring evidence fields/cards.

---

## 10. Cards and modules

Comparable modules use consistent:
- border/radius;
- background;
- padding;
- heading position;
- internal spacing.

Do not make one evidence module materially taller/wider without content reason.

---

## 11. Responsive behavior

At minimum visually inspect:
- standard desktop;
- narrower laptop/tablet-like width;
- phone/resource-portal width where applicable.

Requirements:
- no horizontal overflow from helper text;
- action rows wrap intentionally;
- icons stay attached to labels;
- cards stack in a logical order;
- tables provide usable overflow/alternative layout.

---

## 12. Accessibility basics

- semantic labels for form controls;
- buttons are real buttons;
- icons with interaction have accessible name/tooltips;
- keyboard focus visible;
- errors not conveyed only by color;
- touch targets remain usable.

---

## 13. Page-specific current QA — Resource profile

Before declaring the current Resource profile UI complete, inspect all of the following together:

- test-card heading/readability;
- `Tests & Qualifications` alignment;
- `Save changes` and `Assign Test` alignment;
- `Compliance` heading and section alignment;
- `Account Qualifications from approved jobs` alignment;
- help/question icon positioning;
- text containment in all information bubbles;
- button consistency;
- education/upload card sizing;
- field background contrast;
- consistent content width and left edge across sections.

The user should not have to report the same class of visual defect one by one.


---

## 13. Session-role QA

When Admin and Resource are tested simultaneously:
- use separate browser profiles or Incognito;
- do not intentionally share one Supabase session between roles;
- Update 056 contains a role-drift redirect guard, but this is not a replacement for clean isolated QA sessions.

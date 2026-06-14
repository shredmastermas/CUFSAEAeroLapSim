# Airfoil & Multi-Element Wing Selection — Plan

**Goal.** Turn a target from the manufacturable sweep — `(CL, L/D, CoP)` — into a
*buildable* front + rear wing: which airfoils, how many elements, their sizes,
and their arrangement (gap, overlap, deflection, stagger). Add a NACA / airfoil
generator and a multi-element layout tool so the team can *design* the wing that
produces the numbers the lap sim is optimizing over, instead of guessing.

This plan is written to **extend what already exists**, not restart it.

---

## 0. What's already in the repo (the starting point)

- **`pylapsim/airfoils.py`** — real, tested module:
  - `load_coordinates(name)`, `load_polar(name, re)`, `polar_summary(name, re)` → `cl_max`, `alpha@clmax`, `cd@clmax`, source URL.
  - `cla_from_cl_target(cl)` → required `CL·A` (ft², m²) from a sim coefficient.
  - **`suggest_wings(cl, cd, cop)`** → per-wing `CL·A` demand, candidate **single** airfoils, required area at an (unsourced, labeled) 2D→3D `achieved_CL_fraction`. Every row carries its polar source + the FSAE rules-box citation.
- **`data/airfoils/`** — 5 high-lift sections with Selig `.dat` coordinates **and** airfoiltools XFOIL polars at **Re 200k & 500k** (the FSAE wing Re band at 35–60 mph, 0.25–0.5 m chords), plus `MANIFEST.json` with URLs + sha256:
  - **s1223** (the classic FSAE high-lift, 2D cl_max ≈ 2.2), **e423**, **ch10sm**, **s1210**, **fx74cl5140**.
- **`scripts/fetch_airfoils.py`** — provenance-tracked downloader (extend this to add sections).
- **`tests/test_airfoils.py`** — pattern to copy for new code.

**The gap.** `suggest_wings` sizes a *single* element. Real FSAE wings are
**multi-element** (typically 2–3 element front, 3–4 element rear) because one
element can't reach the per-wing CL the sweep wants (~2.5–4) with attached flow —
it stalls. Everything below is about closing that gap.

---

## 1. Why multi-element (the physics the tool must capture)

A slotted flap doesn't work by "more camber." The slot does five things (Smith,
1975, *"High-Lift Aerodynamics"*) that let elements stack high local CL with the
boundary layer still attached:

1. **Slat/circulation effect** — upstream element reduces the suction peak on the
   downstream element, delaying its stall.
2. **Dumping effect** — trailing edge of an upstream element sits in a high-velocity
   region, so its boundary layer "dumps" energetically instead of separating.
3. **Off-surface pressure recovery** — each element's wake recovers pressure in the
   freestream, not against a wall (less prone to separation).
4. **Fresh-boundary-layer effect** — each element starts a new, thin boundary layer.
5. **Circulation coupling** — net circulation of the stack > sum of isolated elements.

**Consequence for the model:** element interaction is *coupled* — you can't sum
isolated XFOIL polars. The tool needs a method that solves the elements together,
or applies a corrected superposition. This is the central fidelity decision (§4).

---

## 2. Target → requirement (already mostly solved)

For a sweep cell `(CL, L/D, CoP)`:
- Total `CL·A` from `cla_from_cl_target(CL)`; **CD·A = CL·A / (L/D)**.
- Front `CL·A = CoP · total`; rear `= (1−CoP) · total` (axle-force split — same
  approximation the lap sim makes; `suggest_wings` already does this).
- Convert to downforce in lbf at any speed with `DF = CL·A · ½ρ V²` (the dashboard
  already shows this @35 and @90 mph).

So the requirement side is done. The work is the **synthesis** side: produce a
geometry whose predicted `(CL·A, CD·A)` meets the requirement within the rules box.

---

## 3. The NACA / airfoil generator (Phase A — geometry)

A small `pylapsim/airfoil_gen.py`:

- **NACA 4-digit** (analytic camber line + thickness) and **5-digit** (incl.
  reflexed) → coordinate arrays in Selig format. Pure functions, easy to test
  against published ordinates.
- **Loaders for the existing Selig sections** (reuse `airfoils.load_coordinates`).
- **Element transform**: `place(coords, chord, x, y, deflection_deg, stagger)` —
  scale to chord, rotate by deflection, translate to a slot position.
- **Multi-element assembly**: an ordered list of placed elements with the four
  layout parameters per joint:
  - **gap** (slot width, normal distance between element TE and next element LE) —
    typical 1.5–4 % of local chord,
  - **overlap** (chordwise; can be negative),
  - **deflection** (each flap angle relative to the main),
  - **chord ratio** (flap chord / main chord, typ. 0.3–0.5).
- **Cross-section renderer** → SVG of the stacked elements (drops straight into the
  dashboard; matches the existing SVG-everywhere style).

Deliverable: given parameters, get coordinates + a drawing. No aero yet.

---

## 4. Multi-element aerodynamics (Phase C — the hard part, pick a fidelity)

XFOIL is **single-element only**, so the existing polars stop here. Options,
cheapest → most accurate:

| Option | What it is | Pros | Cons |
|---|---|---|---|
| **(A) Corrected superposition** | Sum element cls, apply empirical slot-gap/deflection factors (Liebeck, Wolkovitch) | Trivial, instant, uses the XFOIL polars we have | Approximate; coefficients are dataset-specific |
| **(B) 2D vortex-panel + viscous coupling** | Inviscid multi-element panel solve for circulation interaction, then an integral BL for separation/drag | Captures the *coupling* (the whole point); pure-python feasible; fast enough to sweep gaps/deflections | We build/integrate it; BL coupling is finicky near stall |
| **(C) MSES / MSARC** (Drela) | Viscous multi-element Euler+BL, the academic gold standard | Most accurate short of CFD | External binary, build/licensing, steeper to drive headlessly |
| **(D) RANS CFD** | Full 2D/3D Navier-Stokes | Truth | Way out of scope for a design-loop tool |

**Recommendation:** **(B)** as the core, with **(A)** as a fast pre-filter and an
**anchor** — cap predicted element CL by the single-element XFOIL `cl_max` (×
achieved-fraction) so the panel method can't promise attached flow the section
can't hold. Defer **(C)** to a "validate the final candidate" step. This keeps the
design loop in-process and fast while staying honest about stall.

Output of Phase C: for a given stack geometry, `cl(α)`, `cd(α)`, and a
stall-margin flag, at the two Reynolds we already have.

---

## 5. 2D → 3D (Phase D — the wing, not the section)

The sweep wants `CL·A`/`CD·A` of the *installed* wing, so:
- **Finite span + endplates** — endplates raise effective aspect ratio; model with
  lifting-line / VLM. **AVL** or **MachUpX** (both scriptable) take the 2D section
  polars and give 3D `CL`, induced `CD`, and spanload. Start with a simple
  effective-AR knockdown, graduate to VLM.
- **Ground effect** (front wing especially) — large, real, and CoP-shifting. At
  minimum a labeled sensitivity factor; ideally a ground-plane in the VLM.
- **The existing `achieved_CL_fraction`** column already exposes the 2D→3D
  knockdown as a labeled, unsourced sensitivity — keep that honesty; replace the
  guess with the VLM result as it lands.

---

## 6. Sizing & the loop back to the lap sim (Phase E — why this matters)

This is what makes it more than a calculator:

1. Pick a sweep target `(CL, L/D, CoP)` (e.g. the best buildable cell,
   CL0.055 / L/D3.0 / CoP0.55).
2. **Search** element count, chords, deflections, gaps to hit each wing's `CL·A`
   at **min CD·A**, subject to: rules box (chord/height/overlap limits), stall
   margin, and *manufacturing* limits (min slot gap you can actually mold, max
   element count, max chord).
3. Each candidate wing → `(CL, CD, CoP)` → **feed `pylapsim`** → points.
4. Rank candidates by points **and** buildability. The output is "here are 3 wings
   that land near this sweep cell, here's what each scores, here's the drawing and
   the build sheet."

That closes the loop the whole project is about: the sweep says *what aero is
worth*, this tool says *what's buildable and how to build it*, and the lap sim
scores the buildable thing — no fantasy CL.

---

## 7. Dashboard surface (Phase F — "Wing designer" tab)

A new tab consistent with the existing SVG/krugify style:
- Pick a sweep cell (or type CL/L/D/CoP) → shows the front & rear requirement
  (`CL·A`, downforce lbf @35/90).
- Candidate stacks as **cross-section SVGs** (main + flaps + slots), each with
  predicted CL / CD / L/D, stall margin, and a hit/miss vs target.
- Sliders for gap / deflection / chord-ratio with live recompute (panel method is
  fast enough); a "score this in the lap sim" button that returns points + Δ vs the
  reference build.

---

## 8. Phasing (smallest shippable steps)

- **A. Generator + assembler + cross-section SVG** — geometry only, fully testable. *(no new deps)* — **✅ SHIPPED** (dashboard `assembleStack` + `StackSketch`: real UIUC coords scaled to chord, rotated by deflection, slotted by gap/overlap; stacked cross-section render; exact total-chord / stack-height).
- **B. Single-element candidate wrapper** — surface `suggest_wings` results as concrete wings with the XFOIL polars. *(done-ish; just present it)* — **✅ SHIPPED** (Real-world wing tab, single-element sizing table).
- **C. Multi-element 2D solver** — option (B) panel+BL with the (A) anchor; sweep gap/deflection. *(core engineering)* — **⏳ C-lite SHIPPED** as the dashboard `MultiElementDesigner`: the Option-A pre-filter (stack 2D cl_max ≈ η·Σ XFOIL cl_max, anchored on real single-element cl_max, × a labeled 2D→3D fraction), live gap/overlap/deflection/element-count controls, area-vs-single-element win, stall-risk flag. **C-full (the real panel+viscous-BL solver) is still the long pole** — it replaces η and the 2D→3D fraction with computed values.
- **D. 3D** — effective-AR knockdown → AVL/MachUpX VLM with endplates + ground plane.
- **E. Sizing search + lap-sim coupling** — the design loop.
- **F. "Wing designer" dashboard tab.** — partially realized inside the Real-world wing tab (designer is live); a dedicated tab + the sizing search (E) remain.

A + B + C-lite are live in the dashboard. **C-full (viscous multi-element solver) is the next real engineering lift**, then D (3D/ground effect) and E (sizing search coupled to the lap sim).

---

## 9. Decisions needed before building (for Mason / the team)

1. **Fidelity for §4** — panel+empirical (recommended, in-process) vs commit to
   MSES (more accurate, external binary)? Drives the whole effort.
2. **Element counts to allow** — what's the real manufacturing ceiling (2-/3-/4-element)?
   And the **min slot gap** the team can actually mold (sets the design lower bound).
3. **Ground effect** — model it (front wing CoP depends on it) or hold it as a
   labeled sensitivity for v1?
4. **Rules box** — confirm the 2026 FSAE aero envelope (chord, height, overlap,
   width, leading/trailing-edge limits). `suggest_wings` already cites a `RULES_BOX`;
   reconcile with the current rulebook (`/tmp/fsae_rules_2026.pdf` is on disk).
5. **Airfoil shortlist** — keep generating NACA sections, or restrict to the proven
   FSAE high-lift family already in-repo (s1223-led) + their flap pairings?

---

## 10. Honest limits

- The 2D→3D knockdown and ground effect are the biggest uncertainties; both are
  surfaced as labeled sensitivities, not hidden.
- Panel-method CL near stall is optimistic by construction — the single-element
  XFOIL `cl_max` anchor exists to keep it honest, and the final candidate should be
  validated in MSES (or against published FSAE multi-element data) before it's
  trusted as an absolute.
- The polars are airfoiltools XFOIL computations (Ncrit 9, M 0), **not** wind tunnel
  — fine for *relative* design, flagged for *absolute* claims (already noted in `MANIFEST.json`).
```

# Studio visual direction

These reference boards pin the intended visual language for Studio. They are direction,
not pixel-perfect product specifications: Studio should adopt their hierarchy, density,
materials, and interaction cues without copying the unrelated monster branding or sample
content.

- [Dashboard and shell reference](../assets/studio/dashboard-reference.png) — global
  navigation, content cards, record detail, inventory-like palettes, and modal treatment.
- [Map editor reference](../assets/studio/map-editor-reference.png) — the primary Phase-5
  workspace reference: tool rail, tileset palette, map canvas, action bar, inspector, and
  layer list.

The original working copies live under `build/preview/concept/`; that tree is ignored.
The copies above are the durable repository references.

## Product character

Studio is a focused desktop creation tool: dark, calm, tactile, and compact enough to keep
the creator's work dominant. Pixel-art project content supplies the colour and personality;
the shell should recede around it. The interface may feel game-adjacent, but it must remain
legible and predictable as an editor.

The recurring visual vocabulary is:

- deep charcoal window and panel surfaces, separated by restrained borders and soft depth;
- off-white primary text with muted blue-grey labels and secondary information;
- mint-to-cyan accents for focus, selection, success, and primary actions;
- occasional magenta for special authored entities such as triggers or spawn nodes, not as
  a second general-purpose selection colour;
- rounded panels, controls, cards, and selected tiles with a consistent modest radius;
- crisp project pixels inside preview wells and canvases, never blurred by UI scaling;
- compact icon-plus-label controls, with text or tooltips wherever an icon is ambiguous.

Selection may glow, but glow is reinforcement rather than the only signal: selected tools,
records, tiles, layers, and objects also need a border, fill, marker, or changed label weight.

## Shell hierarchy

The dashboard board governs Studio-wide surfaces. Use a narrow persistent navigation rail
for major workspaces, then give the active workspace the remaining area. Within content
editors, favor a browsable card/list region and a clear detail or form surface. Floating
detail panels and dialogs use the same material as docked panels and must preserve context
behind them.

The repository has no generic-monster product identity to copy from the board. Navigation
names and imagery must describe pokeredpc's actual workspaces and the open creator project.

## Map workspace

The map board governs Phase 5. At a normal desktop size the workspace has three functional
columns:

1. a compact tool rail plus tileset/object palette on the left;
2. a dominant, pannable and zoomable map canvas in the centre;
3. an inspector and layer list on the right.

A short action bar above the canvas contains document actions, undo/redo, play-test, zoom,
and the active tileset. The canvas owns available space and may collapse the inspector or
palette before becoming unusably small. Grid, collision, object, and trigger overlays remain
visually distinct from the authored art. A creator must be able to identify the active tool,
selected palette item, selected map entity, active layer, dirty state, and validation state
without guessing.

Phase 5.1's read-only tracer should already establish this composition even when some rails
contain placeholders. Phase 5.3 fills those surfaces with painting, collision, block-brush,
and undo controls rather than replacing the composition.

## Scale and accessibility

Studio uses a native resizable desktop window (ADR-020, gh #59), not the game's 160×144
scaled viewport. Layout must remain usable at the 900×600 minimum and breathe at 1280×800
and above. At the minimum size, secondary docks may collapse or scroll; the primary action
and the active document must remain reachable.

The top bar exposes a persistent **UI scale** slider from 80% to 200%, defaulting to 125%.
It scales editor chrome, controls, and text through the Window content scale while allowing
the layout to reflow. This is distinct from map zoom, which changes only authored pixels.
The user setting wins over guessed operating-system DPI, especially on Windows where Godot
cannot reliably query the display scale.

Use readable desktop type sizes, at least 32-pixel practical pointer targets for dense
tools, keyboard focus indicators, and contrast sufficient for labels over every surface.
Do not encode collision, validation, or layer state using colour alone. Project pixels use
nearest-neighbour sampling; UI decoration can use normal filtered rendering.

## Implementation guardrail

Centralize this palette and control styling in one Studio theme/factory rather than styling
each screen independently. New work should be compared against both reference boards and
this contract during review. When a functional constraint requires divergence, preserve the
information hierarchy first and record any lasting new convention here.

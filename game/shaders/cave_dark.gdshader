shader_type canvas_item;
// Gen-1 dark cave: a full-screen PALETTE swap, not a spotlight (gh #127). Entering Rock Tunnel,
// pokered sets wMapPalOffset = $06 (home/overworld.asm .notRockTunnel), so LoadGBPal loads FadePal2
// (home/fade.asm) whose BGP/OBP0 = 3,3,3,2: the lightest of the four DMG shades maps to shade 2 and
// every darker shade maps to shade 3 (black). The whole screen dims uniformly; FLASH restores the
// normal palette (Main hides this overlay). We reproduce it by remapping the rendered screen's four
// shades to that dark palette.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// The two DMG green shades FadePal2 collapses everything into (the port's tileset/sprite palette).
const vec3 SHADE2 = vec3(101.0, 138.0, 114.0) / 255.0;   // FadePal2 target for the lightest shade
const vec3 SHADE3 = vec3( 34.0,  48.0,  57.0) / 255.0;   // ...every other shade -> black

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	// Only the lightest shade (lum ~0.93) survives, as dark grey; shades 1-3 all become black.
	COLOR = vec4(lum > 0.85 ? SHADE2 : SHADE3, 1.0);
}

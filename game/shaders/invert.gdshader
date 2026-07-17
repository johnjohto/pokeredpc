shader_type canvas_item;

// True palette inversion for AnimationFlashScreen (the GB writes the inverted BGP): the
// battle flash flips every shade instead of overlaying an alpha rect.
uniform sampler2D screen_tex : hint_screen_texture;

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	COLOR = vec4(1.0 - c.rgb, 1.0);
}

shader_type canvas_item;

// Tall-grass leg overlap: the grass tile is drawn over the player's lower half, but
// only the grass *blades* should obscure the legs. On the Game Boy the sprite sits
// behind BG colors 1-3 and in front of BG color 0 (the lightest shade = the gaps
// between blades). So discard the lightest GB shade here to let the legs show through.
//
// Lightest GB green (GB_PALETTE[0] in tools/extract.py) = (224,248,208)/255.
const vec3 GAP = vec3(0.878, 0.973, 0.816);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (distance(c.rgb, GAP) < 0.06) {
		discard;
	}
	COLOR = c;
}

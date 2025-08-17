shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 sand_tint : hint_color = vec4(0.85, 0.76, 0.60, 1.0);
uniform float speed = 0.15;
uniform float density = 35.0;

float hash(vec2 p){
	p = fract(p*vec2(123.34, 345.45));
	p += dot(p, p+34.345);
	return fract(p.x*p.y);
}

void fragment(){
	vec2 p = FRAGCOORD.xy / 256.0;
	float t = TIME * speed;
	float n = 0.0;
	for(int i=0;i<3;i++){
		vec2 q = p * (density * float(i+1));
		n += hash(q + t);
	}
	n /= 3.0;
	vec4 base = sand_tint * (0.85 + 0.15 * n);
	COLOR = base;
}

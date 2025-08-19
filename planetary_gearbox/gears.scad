// Simple parametric gear primitives for printable demo planetary gearboxes
// Note: This is a simplified tooth geometry (not true involute). Good for demo/toy loads.
// Units: millimeters

// =====================
// Utility
// =====================
function deg2rad(a) = a * PI / 180;
function rad2deg(a) = a * 180 / PI;

// Point on a circle for angle in degrees
function circle_pt(r, a_deg) = [ r * cos(deg2rad(a_deg)), r * sin(deg2rad(a_deg)) ];

// Generate a wedge-shaped ring sector polygon between radii [r_in, r_out] and +/- ang/2
// segs controls discretization of the arcs
module ring_wedge(r_in, r_out, ang_deg, segs=6) {
	ang_half = ang_deg/2;
	outer_pts = [ for (i=[0:segs]) circle_pt(r_out, -ang_half + i*(ang_deg/segs)) ];
	inner_pts = [ for (i=[0:segs]) circle_pt(r_in, ang_half - i*(ang_deg/segs)) ];
	polygon(points = concat(outer_pts, inner_pts));
}

// =====================
// External gear (simplified)
// =====================
// Parameters:
// - z: number of teeth
// - m: module (mm)
// - thickness: extrusion thickness (mm)
// - tooth_fraction: fraction of pitch allocated to tooth thickness at pitch circle (0.0-1.0). 0.45 recommended for backlash
// - addendum, dedendum: standard gear proportions
// - backlash_angle_extra: extra angular clearance added to each tooth space (deg)
// - bore_diameter: center bore diameter (mm)
module external_gear_3d(z=20, m=1.6, thickness=8, tooth_fraction=0.45, addendum_mul=1.0, dedendum_mul=1.25, backlash_angle_extra=0.0, bore_diameter=5.0, fn_outer=120) {
	pitch_d = m * z;
	pitch_r = pitch_d / 2;
	addendum = addendum_mul * m;
	dedendum = dedendum_mul * m;
	outer_r = pitch_r + addendum;
	root_r = max(0.1, pitch_r - dedendum);
	pitch_ang = 360 / z;
	tooth_ang = pitch_ang * tooth_fraction;
	space_ang = pitch_ang - tooth_ang + backlash_angle_extra;
	$fn = fn_outer;

	linear_extrude(height=thickness) difference() {
		circle(r=outer_r);
		// Cut tooth spaces as wedges
		for (i=[0:z-1]) rotate(i*pitch_ang)
			ring_wedge(r_in=root_r, r_out=outer_r+0.2, ang_deg=space_ang, segs=6);
		// Center bore
		circle(r=bore_diameter/2);
	}
}

// =====================
// Internal gear (simplified)
// =====================
// Creates a ring gear body with inward-pointing simplified teeth
// Parameters:
// - z: number of internal teeth
// - m: module (mm)
// - thickness: extrusion thickness (mm)
// - tooth_fraction: see external
// - ring_wall: extra wall thickness outside the tooth root (mm)
// - backlash_angle_extra: extra angular clearance added to each tooth space (deg)
// - bore_diameter: through bore (optional)
module internal_ring_gear_3d(z=50, m=1.6, thickness=12, tooth_fraction=0.45, ring_wall=3.0, addendum_mul=1.0, dedendum_mul=1.25, backlash_angle_extra=0.0, bore_diameter=0, fn_outer=160) {
	pitch_d = m * z;
	pitch_r = pitch_d / 2;
	addendum = addendum_mul * m;   // tooth tip towards center
	dedendum = dedendum_mul * m;   // towards outside
	inner_tip_r = max(0.1, pitch_r - addendum); // smallest radius (tooth tips)
	inner_root_r = pitch_r + dedendum;          // largest inner radius (tooth valleys)
	ring_outer_r = inner_root_r + ring_wall;    // body outside the teeth
	pitch_ang = 360 / z;
	tooth_ang = pitch_ang * tooth_fraction;
	space_ang = pitch_ang - tooth_ang + backlash_angle_extra; // space cuts between internal teeth
	$fn = fn_outer;

	linear_extrude(height=thickness) difference() {
		// Solid ring body
		circle(r=ring_outer_r);
		// Carve inner bore to the tooth valleys
		circle(r=inner_root_r);
		// Carve spaces between internal teeth as wedges protruding inward
		for (i=[0:z-1]) rotate(i*pitch_ang)
			ring_wedge(r_in=inner_tip_r-0.2, r_out=inner_root_r+0.2, ang_deg=space_ang, segs=6);
		// Optional through bore
		if (bore_diameter > 0)
			circle(r=bore_diameter/2);
	}
}

// =====================
// Helper: circular array placement
// =====================
module around(radius, count) {
	for (i=[0:count-1])
		rotate([0,0,i*(360/count)]) translate([radius,0,0]) children();
}
// Parametric printable planetary gearbox (simplified tooth geometry)
// Author: AI assistant
// Units: millimeters

include <gears.scad>

// =====================
// Global parameters (tweak as needed)
// =====================
part = "assembly"; // options: assembly | sun | planet | ring | carrier_top | carrier_bottom | spacer

// Gear train
m = 1.6;                 // module (mm)
z_sun = 12;              // sun gear teeth
z_planet = 18;           // planet gear teeth
n_planets = 3;           // number of planets (3 or 4 typical)
wall = 3.0;              // ring wall thickness (outside tooth root)
tooth_fraction = 0.45;   // 0.40..0.48 recommended for FDM backlash
backlash_angle_extra = 0.5; // extra deg in tooth spaces to loosen mesh

// Thicknesses
gear_thickness = 8;      // sun/planet thickness
ring_thickness = 14;     // ring body thickness (can be taller to form a cup)
carrier_thickness = 4;   // each carrier plate
spacer_thickness = 2;    // optional spacer/washer for top/bottom

// Holes and shafts
center_bore_d = 8.0;     // center shaft bore in carriers & sun
planet_pin_d = 5.0;      // planet pin diameter (print pins or use M5 smooth rod)
bolt_hole_d = 3.2;       // bolt holes in carriers (for M3)
bolt_circle_d = 40;      // bolt circle diameter on carriers

// Body & clearances
clearance_xy = 0.25;     // extra radial clearance for bores
ring_body_lip = 2.0;     // lip to seat a cover/carrier

// Derived
z_ring = z_sun + 2*z_planet;            // relationship for coaxial planetary
pitch_r_sun = (m*z_sun)/2;
pitch_r_planet = (m*z_planet)/2;
pitch_r_ring = (m*z_ring)/2;
planet_center_r = pitch_r_sun + pitch_r_planet; // planet orbit radius

// =====================
// Parts
// =====================
module part_sun() {
	external_gear_3d(
		z=z_sun,
		m=m,
		thickness=gear_thickness,
		tooth_fraction=tooth_fraction,
		addendum_mul=1.0,
		dedendum_mul=1.25,
		backlash_angle_extra=backlash_angle_extra,
		bore_diameter=center_bore_d + clearance_xy
	);
}

module part_planet() {
	external_gear_3d(
		z=z_planet,
		m=m,
		thickness=gear_thickness,
		tooth_fraction=tooth_fraction,
		addendum_mul=1.0,
		dedendum_mul=1.25,
		backlash_angle_extra=backlash_angle_extra,
		bore_diameter=planet_pin_d + clearance_xy
	);
}

module part_ring() {
	internal_ring_gear_3d(
		z=z_ring,
		m=m,
		thickness=ring_thickness,
		tooth_fraction=tooth_fraction,
		ring_wall=wall,
		addendum_mul=1.0,
		dedendum_mul=1.25,
		backlash_angle_extra=backlash_angle_extra,
		bore_diameter=0
	);
}

// Carrier plates (top/bottom)
// - Central bore for shaft
// - Planet pin holes on radius = planet_center_r
// - Bolt circle for closing the sandwich
module part_carrier(is_top=true) {
	d_hub = max(center_bore_d + 6, 2*(pitch_r_sun*0.6));
	plate_r = max(pitch_r_ring + wall + 4, bolt_circle_d/2 + 6);
	linear_extrude(height=carrier_thickness) difference() {
		// outer profile with a small lip recess for the ring
		union() {
			circle(r=plate_r);
			if (is_top) translate([0,0,0]) circle(r=plate_r); // placeholder to keep symmetric
		}
		// center bore
		circle(r=(center_bore_d + clearance_xy)/2);
		// planet pin holes
		for (i=[0:n_planets-1]) rotate(i*360/n_planets)
			translate([planet_center_r,0,0]) circle(r=(planet_pin_d + clearance_xy)/2);
		// bolt holes
		for (i=[0:3]) rotate(i*90)
			translate([bolt_circle_d/2,0,0]) circle(r=bolt_hole_d/2);
	}
}

module part_spacer(diameter=10) {
	linear_extrude(height=spacer_thickness) difference() {
		circle(r=diameter/2);
		circle(r=(diameter/2) - 1.0);
	}
}

// =====================
// Assembly (visualization only)
// =====================
module assembly_view() {
	// Ring as base cup
	color([0.85,0.85,0.9]) translate([0,0,0]) part_ring();
	// Bottom carrier
	color([0.8,0.6,0.4]) translate([0,0,0.1]) part_carrier(is_top=false);
	// Sun at center
	color([0.9,0.2,0.2]) translate([0,0,carrier_thickness + 0.2]) part_sun();
	// Planets
	for (i=[0:n_planets-1])
		color([0.2,0.6,0.9])
			translate([0,0,carrier_thickness + 0.2])
			rotate([0,0,i*(360/n_planets)])
			translate([planet_center_r,0,0])
			part_planet();
	// Top carrier
	color([0.8,0.6,0.4]) translate([0,0,carrier_thickness + gear_thickness + 0.4]) part_carrier(is_top=true);
}

// =====================
// Selector
// =====================
if (part == "sun") part_sun();
else if (part == "planet") part_planet();
else if (part == "ring") part_ring();
else if (part == "carrier_top") part_carrier(is_top=true);
else if (part == "carrier_bottom") part_carrier(is_top=false);
else if (part == "spacer") part_spacer(diameter=10);
else assembly_view();

// Helpful echoes
$echo_parameters = [
	["module", m],
	["z_sun", z_sun],
	["z_planet", z_planet],
	["z_ring", z_ring],
	["n_planets", n_planets],
	["planet_center_r", planet_center_r]
];
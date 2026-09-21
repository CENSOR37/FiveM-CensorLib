-- Change the keyframes here; the movement code stays the same.
return {
    model = "prop_gold_bar",
    duration = 1800,
    curves = {
        pull = cslib.curve.cubic({ { 0, 0 }, { 0.2, 0 }, { 0.45, 0.12 }, { 0.75, 0.65 }, { 1, 1 } }),
        lift = cslib.curve.cubic({ { 0, 0 }, { 0.18, 1.8 }, { 0.45, 2.5 }, { 0.75, 1.1 }, { 1, 0 } }),
        sway = cslib.curve.cubic({ { 0, 0 }, { 0.24, 0.7 }, { 0.55, 1.2 }, { 0.8, 0.4 }, { 1, 0 } }),
        scale = cslib.curve.cubic({ { 0, 0.3 }, { 0.16, 1.2 }, { 0.32, 0.85 }, { 0.5, 1 }, { 0.8, 0.65 }, { 1, 0 } }),
        spin = cslib.curve.linear({ { 0, 0 }, { 0.35, 140 }, { 0.75, 600 }, { 1, 1080 } }),
        glow = cslib.curve.linear({ { 0, 0 }, { 0.16, 2 }, { 0.72, 1.2 }, { 0.95, 3 }, { 1, 0 } }),
    },
}

//! Draws the launch screen's text as vector PDFs into the asset catalog: the dimmed dashes and "FINDING GPS" of the
//! app's waiting state, in Archivo at Paper.swift's settings (a launch screen can't use a bundled variable font, so
//! LaunchScreen.storyboard places these images to the same numbers instead). Each image is its text's CSS line box:
//! the advance (letter spacing included) wide and the line height tall, the baseline where WebKit puts it, so the
//! storyboard pins its edges where Paper pins the text. Run from the repo root: `cargo run --manifest-path
//! tools/launch-art/Cargo.toml`.
use rustybuzz::ttf_parser::{OutlineBuilder, Tag};
use std::fmt::Write as _;
use std::fs;

const ASCENT: f32 = 0.878;
const DESCENT: f32 = 0.210;

struct Text {
    asset: &'static str,
    text: &'static str,
    size: f32,
    weight: f32,
    width: f32,
    kern: f32, // letter spacing, per em
    line_height: f32,
    baseline: f32, // from the bottom of the line box
    alpha: f32,
}

struct Pdf<'a> {
    path: &'a mut String,
    scale: f32,
    x: f32,
    y: f32,
    last: (f32, f32), // the current point, in page coordinates
}

impl Pdf<'_> {
    fn point(&self, x: f32, y: f32) -> (f32, f32) { (self.x + x * self.scale, self.y + y * self.scale) }
}

impl OutlineBuilder for Pdf<'_> {
    fn move_to(&mut self, x: f32, y: f32) {
        let (x, y) = self.point(x, y);
        writeln!(self.path, "{x:.3} {y:.3} m").unwrap();
        self.last = (x, y);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        let (x, y) = self.point(x, y);
        writeln!(self.path, "{x:.3} {y:.3} l").unwrap();
        self.last = (x, y);
    }
    fn quad_to(&mut self, x1: f32, y1: f32, x: f32, y: f32) {
        // A quadratic as the cubic PDF draws: control points two thirds of the way to the quadratic's one.
        let (x0, y0) = self.last;
        let (qx, qy) = self.point(x1, y1);
        let (x, y) = self.point(x, y);
        let (c1x, c1y) = (x0 + 2.0 / 3.0 * (qx - x0), y0 + 2.0 / 3.0 * (qy - y0));
        let (c2x, c2y) = (x + 2.0 / 3.0 * (qx - x), y + 2.0 / 3.0 * (qy - y));
        writeln!(self.path, "{c1x:.3} {c1y:.3} {c2x:.3} {c2y:.3} {x:.3} {y:.3} c").unwrap();
        self.last = (x, y);
    }
    fn curve_to(&mut self, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) {
        let (x1, y1) = self.point(x1, y1);
        let (x2, y2) = self.point(x2, y2);
        let (x, y) = self.point(x, y);
        writeln!(self.path, "{x1:.3} {y1:.3} {x2:.3} {y2:.3} {x:.3} {y:.3} c").unwrap();
        self.last = (x, y);
    }
    fn close(&mut self) { self.path.push_str("h\n"); }
}

fn pdf(width: f32, height: f32, rgb: [f32; 3], alpha: f32, path: &str) -> Vec<u8> {
    let content = format!("/G gs {} {} {} rg\n{path}f\n", rgb[0], rgb[1], rgb[2]);
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>".to_string(),
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_string(),
        format!(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width:.3} {height:.3}] /Contents 4 0 R \
             /Resources << /ExtGState << /G 5 0 R >> >> >>"
        ),
        format!("<< /Length {} >>\nstream\n{content}endstream", content.len()),
        format!("<< /Type /ExtGState /ca {alpha} >>"),
    ];
    let mut out = String::from("%PDF-1.4\n");
    let mut offsets = Vec::new();
    for (i, object) in objects.iter().enumerate() {
        offsets.push(out.len());
        writeln!(out, "{} 0 obj\n{object}\nendobj", i + 1).unwrap();
    }
    let xref = out.len();
    writeln!(out, "xref\n0 {}\n0000000000 65535 f ", objects.len() + 1).unwrap();
    for offset in offsets {
        writeln!(out, "{offset:010} 00000 n ").unwrap();
    }
    write!(out, "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n", objects.len() + 1).unwrap();
    out.into_bytes()
}

fn main() {
    let font = fs::read("ios/App/Web/Archivo.ttf").expect("run from the repo root");
    let texts = [
        // Paper's number at a reference size of 100 pt: the storyboard scales it to min(82% width, 60% height) / 3.
        // Its line box is 0.8 em; the baseline sits (0.8 − ascent − descent)/2 + descent above its bottom.
        Text {
            asset: "LaunchDashes",
            text: "– –",
            size: 100.0,
            weight: 900.0,
            width: 68.0,
            kern: -0.02,
            line_height: 80.0,
            baseline: 100.0 * ((0.8 - ASCENT - DESCENT) / 2.0 + DESCENT),
            alpha: 0.25,
        },
        // The 12 pt status, line-height normal: 11 + 3 points, baseline 3 above the bottom.
        Text {
            asset: "LaunchStatus",
            text: "FINDING GPS",
            size: 12.0,
            weight: 700.0,
            width: 100.0,
            kern: 0.18,
            line_height: 14.0,
            baseline: 3.0,
            alpha: 1.0,
        },
    ];
    let inks = [("light", [0.067, 0.067, 0.067]), ("dark", [0.957, 0.949, 0.933])];
    for t in &texts {
        let mut face = rustybuzz::Face::from_slice(&font, 0).unwrap();
        face.set_variation(Tag::from_bytes(b"wght"), t.weight);
        face.set_variation(Tag::from_bytes(b"wdth"), t.width);
        let mut buffer = rustybuzz::UnicodeBuffer::new();
        buffer.push_str(t.text);
        let features = [rustybuzz::Feature::new(Tag::from_bytes(b"tnum"), 1, ..)];
        let glyphs = rustybuzz::shape(&face, &features, buffer);
        let scale = t.size / face.units_per_em() as f32;

        let mut path = String::new();
        let mut x = 0.0;
        for (info, pos) in glyphs.glyph_infos().iter().zip(glyphs.glyph_positions()) {
            let mut pen = Pdf { path: &mut path, scale, x: x + pos.x_offset as f32 * scale, y: t.baseline, last: (0.0, 0.0) };
            face.outline_glyph(rustybuzz::ttf_parser::GlyphId(info.glyph_id as u16), &mut pen);
            x += pos.x_advance as f32 * scale + t.kern * t.size;
        }

        let dir = format!("ios/App/Assets.xcassets/{}.imageset", t.asset);
        fs::create_dir_all(&dir).unwrap();
        // A negative letter spacing after the last glyph would crop it; a positive one stays, as CSS counts it.
        let x = x - (t.kern * t.size).min(0.0);
        for (appearance, rgb) in inks {
            fs::write(format!("{dir}/{}-{appearance}.pdf", t.asset), pdf(x, t.line_height, rgb, t.alpha, &path))
                .unwrap();
        }
        let contents = format!(
            r#"{{
  "images" : [
    {{ "filename" : "{a}-light.pdf", "idiom" : "universal" }},
    {{ "appearances" : [ {{ "appearance" : "luminosity", "value" : "dark" }} ], "filename" : "{a}-dark.pdf", "idiom" : "universal" }}
  ],
  "info" : {{ "author" : "xcode", "version" : 1 }},
  "properties" : {{ "preserves-vector-representation" : true }}
}}
"#,
            a = t.asset
        );
        fs::write(format!("{dir}/Contents.json"), contents).unwrap();
        println!("{}: {x:.3} × {} pt", t.asset, t.line_height);
    }
}

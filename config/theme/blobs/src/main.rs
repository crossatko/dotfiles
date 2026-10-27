//! theme-blobs: `frame_blobs()` of config/theme/theme.py (the standout-accent pass), natively.
//!
//! The same algorithm with the same float operations in the same order, so the results equal the Python reference
//! (which stays in theme.py as the fallback and the oracle of selftest.py): CPython's compensated `sum()` and its
//! `math.hypot` / `math.dist` (vector_norm) are reproduced, every constant and the sRGB linearisation table come from
//! theme.py on the first line of the input.
//!
//! stdin:  "theme-blobs <VERSION>\n" "<params: SO_* constants, then the 256 _LIN values, space separated>\n" then per
//!         frame "F <w> <h> <W> <H> <fine 0|1>\n" + coarse RGB bytes (w*h*3) [+ fine RGB bytes (W*H*3) + mask (W*H)]
//! stdout: per frame one "B <hue> <score> <sum r> <sum g> <sum b> <n>" line per blob (theme.py blob_sums), then "E".
//! `theme-blobs --version` prints the protocol version; `--math` evaluates "h a b" / "d x y z x y z" / "s v..." lines
//! (hypot / dist / sum) for selftest.py's bit-exactness check.
use std::io::{self, BufRead, BufWriter, Read, Write};

const VERSION: u32 = 1;

// ---- CPython float semantics ------------------------------------------------------------------------------------------
fn frexp_e(x: f64) -> i32 {
    // exponent e with x = m * 2^e, 0.5 <= m < 1 (x finite, > 0)
    let bits = x.to_bits();
    let exp = ((bits >> 52) & 0x7ff) as i32;
    if exp == 0 {
        let m = x * f64::powi(2.0, 54);
        return frexp_e(m) - 54;
    }
    exp - 1022
}

fn ldexp1(e: i32) -> f64 {
    // 2^e for -1022 <= e <= 1023
    f64::from_bits(((e + 1023) as u64) << 52)
}

fn dl_mul(x: f64, y: f64) -> (f64, f64) {
    let z = x * y;
    (z, x.mul_add(y, -z))
}

fn dl_fast_sum(a: f64, b: f64) -> (f64, f64) {
    let x = a + b;
    let z = x - a;
    (x, b - z)
}

/// CPython Modules/mathmodule.c vector_norm (math.hypot, math.dist): `v` = absolute values, `max` their maximum.
fn vector_norm(v: &mut [f64], max: f64) -> f64 {
    if max.is_infinite() {
        return max;
    }
    if max.is_nan() {
        return f64::NAN;
    }
    if max == 0.0 || v.len() <= 1 {
        return max;
    }
    let max_e = frexp_e(max);
    if max_e < -1023 {
        for x in v.iter_mut() {
            *x /= f64::MIN_POSITIVE;
        }
        return f64::MIN_POSITIVE * vector_norm(v, max / f64::MIN_POSITIVE);
    }
    let scale = ldexp1(-max_e);
    let (mut csum, mut frac1, mut frac2) = (1.0f64, 0.0f64, 0.0f64);
    for &x0 in v.iter() {
        let x = x0 * scale;
        let (hi, lo) = dl_mul(x, x);
        let (s, t) = dl_fast_sum(csum, hi);
        csum = s;
        frac1 += lo;
        frac2 += t;
    }
    let mut h = (csum - 1.0 + (frac1 + frac2)).sqrt();
    let (hi, lo) = dl_mul(-h, h);
    let (s, t) = dl_fast_sum(csum, hi);
    csum = s;
    frac1 += lo;
    frac2 += t;
    let x = csum - 1.0 + (frac1 + frac2);
    h += x / (2.0 * h);
    h / scale
}

fn hypot(a: f64, b: f64) -> f64 {
    let (x, y) = (a.abs(), b.abs());
    let mut v = [x, y];
    vector_norm(&mut v, if x.is_nan() || y.is_nan() { f64::NAN } else { x.max(y) })
}

fn dist3(p: (f64, f64, f64), q: (f64, f64, f64)) -> f64 {
    let mut v = [(p.0 - q.0).abs(), (p.1 - q.1).abs(), (p.2 - q.2).abs()];
    let m = v[0].max(v[1]).max(v[2]);
    vector_norm(&mut v, m)
}

/// builtin sum() of floats (start 0): the first item as is, then Neumaier's compensated summation.
fn py_sum<I: Iterator<Item = f64>>(mut it: I) -> f64 {
    let mut f = match it.next() {
        Some(x) => 0.0 + x,
        None => return 0.0,
    };
    let mut c = 0.0f64;
    for x in it {
        let t = f + x;
        if f.abs() >= x.abs() {
            c += (f - t) + x;
        } else {
            c += (x - t) + f;
        }
        f = t;
    }
    if c != 0.0 && c.is_finite() {
        f += c;
    }
    f
}

fn py_mod(x: f64, w: f64) -> f64 {
    let m = x % w;
    if m != 0.0 {
        if (w < 0.0) != (m < 0.0) {
            m + w
        } else {
            m
        }
    } else {
        0.0f64.copysign(w)
    }
}

// ---- the analysis -------------------------------------------------------------------------------------------------------
struct P {
    margin: f64, min_c: f64, l_lo: f64, l_hi: f64, join: f64, min_area: f64, min_px: f64, full_area: f64, max_area: f64,
    fine_min_px: usize, fine_max_px: usize, fine_fill: f64, fine_side: usize, fine_iso: f64, fine_busy: f64, tiny_c: f64,
    c_ref: f64, tiny_local: f64, lin: Vec<f64>,
}

type Lab = (f64, f64, f64);

fn oklab(p: &P, r: u8, g: u8, b: u8) -> Lab {
    let (r, g, b) = (p.lin[r as usize], p.lin[g as usize], p.lin[b as usize]);
    let third = 1.0 / 3.0;
    let l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b).powf(third);
    let m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b).powf(third);
    let s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b).powf(third);
    (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}

/// theme.py _blobs: 4-connected same-hue blobs over the candidate pixels (`cand` in increasing index order).
fn blobs(p: &P, cand: &[usize], is_cand: &[bool], lab: &[Lab], w: usize, x_lo: usize, x_hi: usize, y_lo: usize, y_hi: usize,
         max_px: usize, label: &mut Vec<u32>) -> Vec<Vec<usize>> {
    let cosj = p.join.cos();
    let mut out: Vec<Vec<usize>> = Vec::new();
    for &i0 in cand {
        if label[i0] != 0 {
            continue;
        }
        let (_, a0, b0) = lab[i0];
        let c0 = hypot(a0, b0);
        let (ua, ub) = (a0 / c0, b0 / c0);
        let lid = out.len() as u32 + 1;
        label[i0] = lid;
        let mut stack = vec![i0];
        let mut mem = Vec::new();
        while let Some(i) = stack.pop() {
            mem.push(i);
            if max_px > 0 && mem.len() > max_px {
                break;
            }
            let (x, y) = (i % w, i / w);
            let nb = [if x > x_lo { Some(i - 1) } else { None }, if x < x_hi { Some(i + 1) } else { None },
                      if y > y_lo { Some(i - w) } else { None }, if y < y_hi { Some(i + w) } else { None }];
            for j in nb.into_iter().flatten() {
                if is_cand[j] && label[j] == 0 {
                    let (_, a, b) = lab[j];
                    if a * ua + b * ub >= cosj * hypot(a, b) {
                        label[j] = lid;
                        stack.push(j);
                    }
                }
            }
        }
        out.push(mem);
    }
    out
}

struct Blob {
    hue: f64,
    score: f64,
    sums: [u64; 3],
    n: usize,
}

fn frame_blobs(p: &P, w: usize, h: usize, px: &[u8], fine: Option<(usize, usize, &[u8], &[u8])>) -> Vec<Blob> {
    let lab: Vec<Lab> = (0..w * h).map(|i| oklab(p, px[3 * i], px[3 * i + 1], px[3 * i + 2])).collect();
    let (mx, my) = ((w as f64 * p.margin) as usize, (h as f64 * p.margin) as usize);
    if (w as i64) - 2 * (mx as i64) < 3 || (h as i64) - 2 * (my as i64) < 3 {
        return Vec::new();
    }
    let inner = ((w - 2 * mx) * (h - 2 * my)) as f64;
    let (mut sa, mut sb) = (0.0f64, 0.0f64);
    let mut cand = Vec::new();
    let mut is_cand = vec![false; w * h];
    let minc2 = p.min_c * p.min_c;
    for y in my..h - my {
        for x in mx..w - mx {
            let i = y * w + x;
            let (l, a, b) = lab[i];
            sa += a;
            sb += b;
            if p.l_lo <= l && l <= p.l_hi && a * a + b * b >= minc2 {
                cand.push(i);
                is_cand[i] = true;
            }
        }
    }
    let (ma, mb) = (sa / inner, sb / inner);

    // mean OKLab of the coarse grid in the padded box, without the cells skip(i, x, y)
    let surround = |x0: usize, x1: usize, y0: usize, y1: usize, skip: &dyn Fn(usize, usize, usize) -> bool, pad: usize| -> Option<Lab> {
        let (mut s0, mut s1, mut s2, mut sn) = (0.0f64, 0.0f64, 0.0f64, 0usize);
        for y in y0.saturating_sub(pad)..h.min(y1 + pad + 1) {
            for x in x0.saturating_sub(pad)..w.min(x1 + pad + 1) {
                let i = y * w + x;
                if !skip(i, x, y) {
                    let q = lab[i];
                    s0 += q.0;
                    s1 += q.1;
                    s2 += q.2;
                    sn += 1;
                }
            }
        }
        if sn > 0 { Some((s0 / sn as f64, s1 / sn as f64, s2 / sn as f64)) } else { None }
    };
    let score = |k: usize, area: f64, l: f64, a: f64, b: f64, sur: Lab| -> (f64, f64, f64, f64) {
        let c = hypot(a, b);
        let hue = b.atan2(a);
        let local = dist3((l, a, b), sur);
        let novelty = f64::min(1.0, hypot(a - ma, b - mb) / f64::max(c, 0.05));
        let size = f64::min(1.0, k as f64 / (p.full_area * area)).powf(0.5);
        let deg = py_mod(hue * (180.0 / std::f64::consts::PI), 360.0);
        let skin = if 35.0 <= deg && deg <= 80.0 && l >= 0.55 && c <= 0.13 { 0.3 } else { 1.0 };
        (hue, c, local, c * (c / p.c_ref) * local * (0.25 + 0.75 * novelty) * size * skin)
    };
    let vivid_sums = |mem: &[usize], labf: &dyn Fn(usize) -> Lab, rgb: &dyn Fn(usize) -> [u8; 3]| -> ([u64; 3], usize) {
        let mut idx: Vec<(f64, usize)> = mem.iter().map(|&i| { let q = labf(i); (-(q.1.powf(2.0) + q.2.powf(2.0)), i) }).collect();
        idx.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));   // stable, as sorted()
        let n = std::cmp::max(4, mem.len() / 2).min(idx.len());
        let mut s = [0u64; 3];
        for &(_, i) in &idx[..n] {
            let c = rgb(i);
            for k in 0..3 {
                s[k] += c[k] as u64;
            }
        }
        (s, n)
    };

    let mut out = Vec::new();
    let mut label = vec![0u32; w * h];
    let bl = blobs(p, &cand, &is_cand, &lab, w, mx, w - mx - 1, my, h - my - 1, 0, &mut label);
    for (n, mem) in bl.iter().enumerate() {
        let lid = n as u32 + 1;
        let k = mem.len();
        if (k as f64) < f64::max(p.min_px, p.min_area * inner) || k as f64 > p.max_area * inner {
            continue;
        }
        let l = py_sum(mem.iter().map(|&i| lab[i].0)) / k as f64;
        let a = py_sum(mem.iter().map(|&i| lab[i].1)) / k as f64;
        let b = py_sum(mem.iter().map(|&i| lab[i].2)) / k as f64;
        let (x0, x1) = (mem.iter().map(|&i| i % w).min().unwrap(), mem.iter().map(|&i| i % w).max().unwrap());
        let (y0, y1) = (mem.iter().map(|&i| i / w).min().unwrap(), mem.iter().map(|&i| i / w).max().unwrap());
        let lbl = &label;
        let sur = surround(x0, x1, y0, y1, &|i, _, _| lbl[i] == lid, std::cmp::max(2, (x1 - x0 + y1 - y0) / 2));
        let Some(sur) = sur else { continue };
        let (hue, _, _, sc) = score(k, inner, l, a, b, sur);
        let (sums, nv) = vivid_sums(mem, &|i| lab[i], &|i| [px[3 * i], px[3 * i + 1], px[3 * i + 2]]);
        out.push(Blob { hue, score: sc, sums, n: nv });
    }
    let Some((fw, fh, rgb, mask)) = fine else { return out };
    let busy_all = mask.iter().filter(|&&m| m != 0).count();
    if busy_all as f64 > p.fine_busy * mask.len() as f64 {
        return out;
    }
    let (fmx, fmy) = ((fw as f64 * p.margin) as usize, (fh as f64 * p.margin) as usize);
    let area = ((fw - 2 * fmx) * (fh - 2 * fmy)) as f64;
    let mut flab = vec![(0.0f64, 0.0f64, 0.0f64); fw * fh];
    let mut fcand = Vec::new();
    let mut is_fc = vec![false; fw * fh];
    for i in 0..fw * fh {
        if mask[i] == 0 {
            continue;
        }
        let (x, y) = (i % fw, i / fw);
        if x < fmx || x >= fw - fmx || y < fmy || y >= fh - fmy {
            continue;
        }
        let q = oklab(p, rgb[3 * i], rgb[3 * i + 1], rgb[3 * i + 2]);
        if p.l_lo <= q.0 && q.0 <= p.l_hi && q.1 * q.1 + q.2 * q.2 >= minc2 {
            flab[i] = q;
            fcand.push(i);
            is_fc[i] = true;
        }
    }
    let (sx, sy) = (w as f64 / fw as f64, h as f64 / fh as f64);
    let mut flabel = vec![0u32; fw * fh];
    let fb = blobs(p, &fcand, &is_fc, &flab, fw, fmx, fw - fmx - 1, fmy, fh - fmy - 1, p.fine_max_px, &mut flabel);
    let mut own = vec![false; fw * fh];
    for mem in &fb {
        let k = mem.len();
        if k < p.fine_min_px || k > p.fine_max_px {
            continue;
        }
        let (x0, x1) = (mem.iter().map(|&i| i % fw).min().unwrap(), mem.iter().map(|&i| i % fw).max().unwrap());
        let (y0, y1) = (mem.iter().map(|&i| i / fw).min().unwrap(), mem.iter().map(|&i| i / fw).max().unwrap());
        let (bw, bh) = (x1 - x0 + 1, y1 - y0 + 1);
        if bw.min(bh) < p.fine_side || (k as f64) < p.fine_fill * bw as f64 * bh as f64 {
            continue;
        }
        let pad = std::cmp::max(4, (bw + bh) / 2);
        for &i in mem {
            own[i] = true;
        }
        let (mut busy, mut tot) = (0usize, 0usize);
        for y in y0.saturating_sub(pad)..fh.min(y1 + pad + 1) {
            let row = y * fw;
            for x in x0.saturating_sub(pad)..fw.min(x1 + pad + 1) {
                if !own[row + x] {
                    tot += 1;
                    busy += (mask[row + x] != 0) as usize;
                }
            }
        }
        for &i in mem {
            own[i] = false;
        }
        if busy as f64 > p.fine_iso * tot as f64 {
            continue;
        }
        let l = py_sum(mem.iter().map(|&i| flab[i].0)) / k as f64;
        let a = py_sum(mem.iter().map(|&i| flab[i].1)) / k as f64;
        let b = py_sum(mem.iter().map(|&i| flab[i].2)) / k as f64;
        let (cx0, cx1, cy0, cy1) = ((x0 as f64 * sx) as usize, (x1 as f64 * sx) as usize, (y0 as f64 * sy) as usize, (y1 as f64 * sy) as usize);
        let sur = surround(cx0, cx1, cy0, cy1, &|_, x, y| cx0 <= x && x <= cx1 && cy0 <= y && y <= cy1,
                           std::cmp::max(2, (cx1 - cx0 + cy1 - cy0) / 2));
        let Some(sur) = sur else { continue };
        let (hue, c, local, sc) = score(k, area, l, a, b, sur);
        if (k as f64) < p.min_area * area && (c < p.tiny_c || local < p.tiny_local) {
            continue;
        }
        let (sums, nv) = vivid_sums(mem, &|i| flab[i], &|i| [rgb[3 * i], rgb[3 * i + 1], rgb[3 * i + 2]]);
        out.push(Blob { hue, score: sc, sums, n: nv });
    }
    out
}

fn bad(msg: &str) -> ! {
    eprintln!("theme-blobs: {msg}");
    std::process::exit(2)
}

fn math_mode() {
    let stdin = io::stdin();
    let mut out = BufWriter::new(io::stdout().lock());
    for line in stdin.lock().lines() {
        let line = line.unwrap_or_default();
        let mut it = line.split_whitespace();
        let op = it.next().unwrap_or("");
        let v: Vec<f64> = it.map(|x| x.parse().unwrap_or(f64::NAN)).collect();
        let r = match op {
            "h" if v.len() == 2 => hypot(v[0], v[1]),
            "d" if v.len() == 6 => dist3((v[0], v[1], v[2]), (v[3], v[4], v[5])),
            "s" => py_sum(v.into_iter()),
            _ => f64::NAN,
        };
        let _ = writeln!(out, "{r:?}");
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("--version") {
        println!("{VERSION}");
        return;
    }
    if args.get(1).map(String::as_str) == Some("--math") {
        return math_mode();
    }
    let mut input = Vec::new();
    if io::stdin().lock().read_to_end(&mut input).is_err() {
        bad("cannot read stdin");
    }
    let mut pos = 0usize;
    let line = |pos: &mut usize| -> String {
        let end = input[*pos..].iter().position(|&c| c == b'\n').map(|e| *pos + e).unwrap_or_else(|| bad("truncated header"));
        let s = String::from_utf8_lossy(&input[*pos..end]).into_owned();
        *pos = end + 1;
        s
    };
    if line(&mut pos) != format!("theme-blobs {VERSION}") {
        bad("protocol version mismatch");
    }
    let nums: Vec<f64> = line(&mut pos).split_whitespace().map(|x| x.parse().unwrap_or_else(|_| bad("bad parameter"))).collect();
    if nums.len() != 18 + 256 {
        bad("parameter count");
    }
    let p = P {
        margin: nums[0], min_c: nums[1], l_lo: nums[2], l_hi: nums[3], join: nums[4], min_area: nums[5], min_px: nums[6],
        full_area: nums[7], max_area: nums[8], fine_min_px: nums[9] as usize, fine_max_px: nums[10] as usize, fine_fill: nums[11],
        fine_side: nums[12] as usize, fine_iso: nums[13], fine_busy: nums[14], tiny_c: nums[15], c_ref: nums[16], tiny_local: nums[17],
        lin: nums[18..].to_vec(),
    };
    let mut out = BufWriter::new(io::stdout().lock());
    while pos < input.len() {
        let hdr = line(&mut pos);
        let f: Vec<usize> = hdr.split_whitespace().skip(1).map(|x| x.parse().unwrap_or_else(|_| bad("bad frame header"))).collect();
        if !hdr.starts_with("F ") || f.len() != 5 {
            bad("bad frame header");
        }
        let (w, h, fw, fh, has_fine) = (f[0], f[1], f[2], f[3], f[4] == 1);
        let need = w * h * 3 + if has_fine { fw * fh * 4 } else { 0 };
        if input.len() < pos + need {
            bad("truncated frame");
        }
        let px = &input[pos..pos + w * h * 3];
        let fine = if has_fine {
            let o = pos + w * h * 3;
            Some((fw, fh, &input[o..o + fw * fh * 3], &input[o + fw * fh * 3..o + fw * fh * 4]))
        } else {
            None
        };
        for b in frame_blobs(&p, w, h, px, fine) {
            let _ = writeln!(out, "B {:?} {:?} {} {} {} {}", b.hue, b.score, b.sums[0], b.sums[1], b.sums[2], b.n);
        }
        let _ = writeln!(out, "E");
        pos += need;
    }
}

//! Rendering helpers: the view transform, screen options and the conversion to the record.

use crate::{BridgeError, RenderedImage, ViewParams, fail};
use kurbo::Affine;
use vectorcraft_render::{RenderOptions, Rendered};

const MAX_SIDE: f64 = 8192.0;
/// The pasteboard behind the artboards (premultiplied RGBA8).
const PASTEBOARD: [u8; 4] = [226, 226, 230, 255];

fn finite_or(v: f64, d: f64) -> f64 {
    if v.is_finite() { v } else { d }
}

/// Pixel size of the view: points x pixel scale, capped per side.
pub(crate) fn pixel_size(v: &ViewParams) -> (u32, u32) {
    let ppi = finite_or(v.pixel_scale, 1.0).clamp(0.1, 8.0);
    let w = (finite_or(v.width, 1.0) * ppi).round().clamp(1.0, MAX_SIDE);
    let h = (finite_or(v.height, 1.0) * ppi).round().clamp(1.0, MAX_SIDE);
    (w as u32, h as u32)
}

/// `T(w/2, h/2) . S(zoom * ppp) . T(-center)` in pixels, as the desktop canvas builds it.
pub(crate) fn view_affine(v: &ViewParams, w: u32, h: u32) -> Affine {
    let ppi = finite_or(v.pixel_scale, 1.0).clamp(0.1, 8.0);
    let zoom = if v.zoom.is_finite() && v.zoom > 0.0 { v.zoom } else { 1.0 };
    Affine::translate((f64::from(w) / 2.0, f64::from(h) / 2.0)) * Affine::scale(zoom * ppi) * Affine::translate((-finite_or(v.center_x, 0.0), -finite_or(v.center_y, 0.0)))
}

pub(crate) fn screen_options(v: &ViewParams) -> RenderOptions {
    RenderOptions {
        outline: v.outline,
        background: Some(PASTEBOARD),
        artboards: true,
        highlight_substitutions: true,
        progressive_placed: true,
        trace_views: true,
        smooth_images: true,
        image_mips: true,
        ..Default::default()
    }
}

pub(crate) fn to_image(r: Rendered) -> Result<RenderedImage, BridgeError> {
    let need = (r.width as usize).saturating_mul(r.height as usize).saturating_mul(4);
    if r.width == 0 || r.height == 0 || r.pixels.len() < need {
        return Err(fail("the render produced an empty image"));
    }
    let mut rgba = r.pixels;
    rgba.truncate(need);
    Ok(RenderedImage { width: r.width, height: r.height, rgba })
}

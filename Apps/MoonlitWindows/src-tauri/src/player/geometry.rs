use serde::Deserialize;

#[derive(Debug, Clone, Copy, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CssGeometry {
    pub css_left: f64,
    pub css_top: f64,
    pub css_width: f64,
    pub css_height: f64,
    pub css_view_w: f64,
    pub css_view_h: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NativeRect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

pub fn map_css_geometry(css: CssGeometry, native_w: f64, native_h: f64) -> Option<NativeRect> {
    if css.css_view_w <= 0.0 || css.css_view_h <= 0.0 || native_w <= 0.0 || native_h <= 0.0 {
        return None;
    }
    let sx = native_w / css.css_view_w;
    let sy = native_h / css.css_view_h;
    Some(NativeRect {
        x: (css.css_left * sx).round() as i32,
        y: (css.css_top * sy).round() as i32,
        w: (css.css_width * sx).round().max(1.0) as i32,
        h: (css.css_height * sy).round().max(1.0) as i32,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn css(l: f64, t: f64, w: f64, h: f64, vw: f64, vh: f64) -> CssGeometry {
        CssGeometry {
            css_left: l,
            css_top: t,
            css_width: w,
            css_height: h,
            css_view_w: vw,
            css_view_h: vh,
        }
    }

    #[test]
    fn maps_1x_scale_identity() {
        let r = map_css_geometry(
            css(0.0, 0.0, 1280.0, 720.0, 1280.0, 720.0),
            1280.0,
            720.0,
        )
        .unwrap();
        assert_eq!(r, NativeRect { x: 0, y: 0, w: 1280, h: 720 });
    }

    #[test]
    fn maps_150_percent_dpi() {
        let r = map_css_geometry(
            css(100.0, 50.0, 800.0, 450.0, 1280.0, 720.0),
            1920.0,
            1080.0,
        )
        .unwrap();
        assert_eq!(r, NativeRect { x: 150, y: 75, w: 1200, h: 675 });
    }

    #[test]
    fn rejects_degenerate_viewport() {
        assert!(map_css_geometry(
            css(0.0, 0.0, 100.0, 100.0, 0.0, 0.0),
            1920.0,
            1080.0
        )
        .is_none());
    }

    #[test]
    fn clamps_to_min_1px() {
        let r = map_css_geometry(
            css(0.0, 0.0, 0.2, 0.2, 1280.0, 720.0),
            1280.0,
            720.0,
        )
        .unwrap();
        assert_eq!((r.w, r.h), (1, 1));
    }
}

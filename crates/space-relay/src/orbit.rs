use serde::{Deserialize, Serialize};
use crate::satellite::{Satellite, SatelliteId};

pub const EARTH_RADIUS_KM: f64 = 6371.0;
pub const MU_EARTH: f64 = 398_600.4418;

#[derive(Clone, Serialize, Deserialize)]
pub struct Orbit { pub semi_major_km: f64, pub period_s: f64 }

impl Orbit {
    pub fn from_altitude(a: f64) -> Self {
        let r = EARTH_RADIUS_KM + a;
        let p = 2.0 * std::f64::consts::PI * (r.powi(3) / MU_EARTH).sqrt();
        Self { semi_major_km: r, period_s: p }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct GroundStation { pub id: String, pub lat_deg: f64, pub lon_deg: f64, pub min_elevation_deg: f64 }

#[derive(Clone, Serialize, Deserialize)]
pub struct PassWindow {
    pub satellite: SatelliteId, pub station: String,
    pub start_s: f64, pub end_s: f64, pub max_elevation_deg: f64,
    pub kind: crate::satellite::LinkKind,
}

pub struct Constellation { pub sats: Vec<Satellite>, pub stations: Vec<GroundStation> }

impl Constellation {
    pub fn new() -> Self { Self { sats: vec![], stations: vec![] } }
    pub fn add_satellite(&mut self, s: Satellite) { self.sats.push(s); }
    pub fn add_station(&mut self, s: GroundStation) { self.stations.push(s); }
    pub fn passes(&self, t0: f64, horizon: f64) -> Vec<PassWindow> {
        let mut out = Vec::new();
        for sat in &self.sats {
            let o = Orbit::from_altitude(sat.altitude_km);
            for st in &self.stations {
                let step = 5.0;
                let n = (horizon / step) as usize;
                let mut in_p = false; let mut start = 0.0; let mut me = 0.0;
                for i in 0..=n {
                    let t = t0 + i as f64 * step;
                    let el = self.elev(sat, st, t, &o);
                    if el > st.min_elevation_deg {
                        if !in_p { in_p = true; start = t; me = el; } else { me = me.max(el); }
                    } else if in_p {
                        out.push(PassWindow { satellite: sat.id, station: st.id.clone(), start_s: start, end_s: t, max_elevation_deg: me, kind: crate::satellite::LinkKind::Optical });
                        in_p = false;
                    }
                }
                if in_p {
                    out.push(PassWindow { satellite: sat.id, station: st.id.clone(), start_s: start, end_s: t0 + horizon, max_elevation_deg: me, kind: crate::satellite::LinkKind::Optical });
                }
            }
        }
        out
    }
    fn elev(&self, s: &Satellite, g: &GroundStation, t: f64, o: &Orbit) -> f64 {
        let n = 2.0 * std::f64::consts::PI / o.period_s;
        let a = (s.mean_anomaly_deg.to_radians() + n * t).rem_euclid(2.0 * std::f64::consts::PI);
        let i = s.inclination_deg.to_radians();
        let lat = (i.sin() * a.sin()).asin().to_degrees();
        (90.0 - (lat - g.lat_deg).abs()).max(0.0)
    }
}
impl Default for Constellation { fn default() -> Self { Self::new() } }
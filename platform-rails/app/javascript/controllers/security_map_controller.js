import { Controller } from "@hotwired/stimulus"
import jsVectorMap from "jsvectormap"
import "jsvectormap/world"

// World map: country heatmap (total brute-force attempts) + city markers.
// Receives the geo-enriched top_ips array (ip, attempts, country_code,
// country, city, lat, lon) written by security-collect.sh.
export default class extends Controller {
  static values = { points: Array }

  connect() {
    const points = this.pointsValue.filter((p) => p.lat != null && p.lon != null)
    if (points.length === 0) return

    const byCountry = {}
    for (const p of points) {
      if (!p.country_code) continue
      byCountry[p.country_code] = (byCountry[p.country_code] || 0) + p.attempts
    }

    const byCity = {}
    for (const p of points) {
      const key = `${p.city}|${p.lat}|${p.lon}`
      byCity[key] ??= { city: p.city, country: p.country, lat: p.lat, lon: p.lon, attempts: 0 }
      byCity[key].attempts += p.attempts
    }
    const cities = Object.values(byCity)

    this.map = new jsVectorMap({
      selector: this.element,
      map: "world",
      zoomButtons: false,
      zoomOnScrollSpeed: 0.3,
      zoomAnimate: true,
      backgroundColor: "transparent",
      regionStyle: {
        initial: { fill: "var(--color-surface-inset)", stroke: "var(--color-border)", "stroke-width": 0.5 },
        hover: { fill: "var(--color-surface-active)" }
      },
      series: {
        regions: [{ values: byCountry, scale: ["#fde68a", "#dc2626"], attribute: "fill" }]
      },
      markers: cities.map((c) => ({ name: c.city, coords: [c.lat, c.lon] })),
      markerStyle: {
        initial: { fill: "#dc2626", stroke: "#7f1d1d", "fill-opacity": 0.75 }
      },
      markersSelectable: false,
      onMarkerTooltipShow: (_event, tooltip, index) => {
        const c = cities[index]
        tooltip.text(`${c.city}, ${c.country} — ${c.attempts} tentativas`, false)
      },
      onRegionTooltipShow: (_event, tooltip, code) => {
        const n = byCountry[code]
        if (n) tooltip.text(`${tooltip.text()} — ${n} tentativas`, false)
      }
    })

    // jsvectormap sizes its SVG from container.offsetWidth/Height at
    // construction time only. Inside a CSS grid column the final track width
    // isn't always settled on that first measurement, so the map renders
    // undersized/clipped until something else triggers a resize. Force one
    // after layout has had a frame to settle.
    requestAnimationFrame(() => this.map?.updateSize())
  }

  disconnect() {
    this.map?.destroy?.()
    this.map = null
  }
}

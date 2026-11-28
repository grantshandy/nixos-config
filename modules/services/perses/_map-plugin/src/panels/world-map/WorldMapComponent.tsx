import { ReactElement, useMemo } from "react";
import { worldMapCountries } from "../../generated/world-map";
import { WorldMapPoint, WorldMapProps } from "./world-map-types";

const DEFAULT_COLOR = "#ff9800";

function finiteNumber(value: unknown): number | undefined {
  if (typeof value !== "string" && typeof value !== "number") return undefined;
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function validPoint(point: WorldMapPoint): boolean {
  return Number.isFinite(point.latitude) && Number.isFinite(point.longitude) &&
    point.latitude >= -90 && point.latitude <= 90 &&
    point.longitude >= -180 && point.longitude <= 180;
}

export function WorldMapComponent({ queryResults, spec }: WorldMapProps): ReactElement {
  const points = useMemo(() => {
    const latitudeLabel = spec.latitudeLabel ?? "latitude";
    const longitudeLabel = spec.longitudeLabel ?? "longitude";
    const labelLabel = spec.labelLabel ?? "label";
    const valueMode = spec.valueMode ?? "timestamp";
    const queried: WorldMapPoint[] = [];

    for (const result of queryResults ?? []) {
      for (const series of result.data?.series ?? []) {
        const labels = series.labels ?? {};
        const latitude = finiteNumber(labels[latitudeLabel]);
        const longitude = finiteNumber(labels[longitudeLabel]);
        if (latitude === undefined || longitude === undefined) continue;
        const latest = [...series.values].reverse().find(([, value]) => value !== null)?.[1];
        const value = finiteNumber(latest);
        if (valueMode === "timestamp" && result.data?.timeRange &&
            (value === undefined || value * 1000 < result.data.timeRange.start.valueOf())) continue;
        queried.push({
          latitude,
          longitude,
          label: labels[labelLabel] ?? labels.city ?? labels.country ?? series.formattedName ?? series.name,
          color: labels.color,
          size: finiteNumber(labels.size) ?? (valueMode === "size" ? value : undefined),
        });
      }
    }

    return [...(spec.points ?? []), ...queried].filter(validPoint);
  }, [queryResults, spec]);

  const graticule = [30, 60, 90, 120, 150, 210, 240, 270, 300, 330];
  const latitudes = [30, 60, 120, 150];

  return (
    <div style={{ width: "100%", height: "100%", minHeight: 180, display: "grid", placeItems: "center", overflow: "hidden" }}>
      <svg viewBox="0 0 360 180" role="img" aria-label={`World map with ${points.length} points`} style={{ width: "100%", height: "100%", display: "block" }}>
        <rect width="360" height="180" rx="3" fill="#101923" />
        <g stroke="#8aa0b5" strokeOpacity="0.12" strokeWidth="0.35">
          {graticule.map((x) => <line key={`x-${x}`} x1={x} x2={x} y1="0" y2="180" />)}
          {latitudes.map((y) => <line key={`y-${y}`} x1="0" x2="360" y1={y} y2={y} />)}
        </g>
        <g fill="#536776" stroke="#8ba0ad" strokeWidth="0.25" strokeLinejoin="round" fillRule="evenodd">
          {worldMapCountries.map((country) => <path key={country.name} d={country.path}><title>{country.name}</title></path>)}
        </g>
        <g>
          {points.map((point, index) => {
            const x = point.longitude + 180;
            const y = 90 - point.latitude;
            const radius = Math.max(1.8, Math.min(7, point.size ?? 3.2));
            const color = point.color ?? DEFAULT_COLOR;
            const label = point.label ?? `${point.latitude.toFixed(2)}, ${point.longitude.toFixed(2)}`;
            return (
              <g key={`${point.latitude}-${point.longitude}-${label}-${index}`}>
                <circle cx={x} cy={y} r={radius * 2.1} fill={color} opacity="0.16" />
                <circle cx={x} cy={y} r={radius} fill={color} stroke="#fff" strokeOpacity="0.85" strokeWidth="0.65">
                  <title>{label}</title>
                </circle>
              </g>
            );
          })}
        </g>
        {points.length === 0 && <text x="180" y="94" textAnchor="middle" fill="#d7e0e8" fontSize="7">No geographic points in this time range</text>}
      </svg>
    </div>
  );
}

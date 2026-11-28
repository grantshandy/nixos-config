import { PanelProps } from "@perses-dev/plugin-system";
import { TimeSeriesData } from "@perses-dev/spec";

export type QueryData = TimeSeriesData;
export type WorldMapProps = PanelProps<WorldMapOptions, QueryData>;

export interface WorldMapPoint {
  latitude: number;
  longitude: number;
  label?: string;
  color?: string;
  size?: number;
}

export interface WorldMapOptions {
  points?: WorldMapPoint[];
  latitudeLabel?: string;
  longitudeLabel?: string;
  labelLabel?: string;
  valueMode?: "timestamp" | "size" | "ignore";
}

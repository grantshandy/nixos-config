import { PanelPlugin } from "@perses-dev/plugin-system";
import { WorldMapComponent } from "./WorldMapComponent";
import { WorldMapOptions, WorldMapProps } from "./world-map-types";

export const WorldMap: PanelPlugin<WorldMapOptions, WorldMapProps> = {
  PanelComponent: WorldMapComponent,
  supportedQueryTypes: ["TimeSeriesQuery"],
  createInitialOptions: () => ({}),
};

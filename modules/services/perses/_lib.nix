# Builders for the Perses resources this repo provisions.
#
# Imported directly rather than picked up by import-tree -- the leading
# underscore is what keeps it out of the module tree -- by `perses.nix` and by
# every service module that contributes a dashboard, so panel shapes, unit
# names and the 24-column layout arithmetic are written exactly once.
#
# Everything here is plain data: each builder returns the JSON-shaped attrs
# that Perses' own resource model expects, with optional fields dropped rather
# than emitted as nulls (Perses validates plugin specs against closed CUE
# schemas, so a stray key is a provisioning error).
{lib}: let
  # Drop keys a caller left unset, and empty records that pruning produced, so
  # nested specs collapse cleanly from the inside out.
  prune = lib.filterAttrs (_: value: value != null && value != {});

  format = {
    unit ? null,
    decimals ? null,
    shortValues ? null,
  }:
    prune {
      inherit unit shortValues;
      decimalPlaces = decimals;
    };
in rec {
  # Hex, because Perses' threshold and mapping schemas reject colour names.
  colors = {
    green = "#4caf50";
    blue = "#2196f3";
    orange = "#ff9800";
    purple = "#9c27b0";
    red = "#f44336";
    yellow = "#fdd835";
    cyan = "#00bcd4";
    pink = "#e91e63";
    grey = "#9e9e9e";
  };

  # `steps` is a list of `{value, color}`, lowest first; the first step's colour
  # applies from that value upwards.
  thresholds = steps: {
    mode = "absolute";
    inherit steps;
  };

  # A PromQL query against the project's default datasource.
  query = {
    expr,
    legend ? null,
    minStep ? null,
  }: {
    kind = "TimeSeriesQuery";
    spec.plugin = {
      kind = "PrometheusTimeSeriesQuery";
      spec = prune {
        datasource.kind = "PrometheusDatasource";
        query = expr;
        seriesNameFormat = legend;
        inherit minStep;
      };
    };
  };

  panel = {
    kind,
    name,
    description ? null,
    spec ? {},
    queries ? [],
  }: {
    kind = "Panel";
    spec = {
      display = prune {inherit name description;};
      plugin = {inherit kind spec;};
      inherit queries;
    };
  };

  # `querySettings` is how Perses does what Grafana calls field overrides: a
  # list of `{queryIndex, colorValue, negativeY, stack, format, ...}` keyed by
  # position in `queries`.
  timeSeries = {
    name,
    description ? null,
    queries,
    unit ? null,
    decimals ? null,
    shortValues ? null,
    min ? null,
    max ? null,
    label ? null,
    legend ? {
      position = "bottom";
      mode = "list";
    },
    thresholds ? null,
    visual ? null,
    querySettings ? null,
  }:
    panel {
      kind = "TimeSeriesChart";
      inherit name description queries;
      spec = prune {
        inherit legend thresholds visual querySettings;
        yAxis = prune {
          inherit min max label;
          format = format {inherit unit decimals shortValues;};
        };
      };
    };

  gauge = {
    name,
    description ? null,
    queries,
    unit ? null,
    decimals ? null,
    max ? null,
    calculation ? "last-number",
    thresholds ? null,
  }:
    panel {
      kind = "GaugeChart";
      inherit name description queries;
      spec =
        {inherit calculation;}
        // prune {
          inherit max thresholds;
          format = format {inherit unit decimals;};
        };
    };

  stat = {
    name,
    description ? null,
    queries,
    unit ? null,
    decimals ? null,
    shortValues ? null,
    calculation ? "last-number",
    colorMode ? null,
    legendMode ? null,
    metricLabel ? null,
    sparkline ? null,
    thresholds ? null,
    mappings ? null,
  }:
    panel {
      kind = "StatChart";
      inherit name description queries;
      spec =
        {inherit calculation;}
        // prune {
          inherit colorMode legendMode metricLabel sparkline thresholds mappings;
          format = format {inherit unit decimals shortValues;};
        };
    };

  # Maps a value a query returns onto a label and colour, for StatChart.
  mapValue = value: text: color: {
    kind = "Value";
    spec = {
      value = toString value;
      result = {
        value = text;
        inherit color;
      };
    };
  };

  # Lays items out left to right across Perses' 24-column grid, wrapping to a
  # new row whenever the next item would overflow it. Callers therefore give a
  # width and a height per panel and never an (x, y).
  flow = items:
    (lib.foldl' (acc: item: let
        wrapped = acc.x + item.width > 24;
        x =
          if wrapped
          then 0
          else acc.x;
        y =
          if wrapped
          then acc.y + acc.rowHeight
          else acc.y;
      in {
        x = x + item.width;
        inherit y;
        rowHeight =
          if wrapped
          then item.height
          else lib.max acc.rowHeight item.height;
        items =
          acc.items
          ++ [
            {
              inherit x y;
              inherit (item) width height;
              content."$ref" = "#/spec/panels/${item.panel}";
            }
          ];
      }) {
        x = 0;
        y = 0;
        rowHeight = 0;
        items = [];
      }
      items)
    .items;

  # One collapsible section of a dashboard. With `repeat` set to a variable
  # name, Perses renders the whole section once per selected value of that
  # variable, which is how the per-host sections are built.
  group = {
    title ? null,
    open ? true,
    repeat ? null,
    items,
  }: {
    kind = "Grid";
    spec =
      prune {
        display =
          if title == null
          then null
          else {
            inherit title;
            collapse = {inherit open;};
          };
        repeatVariable = repeat;
      }
      // {items = flow items;};
  };

  # A dashboard variable whose options are the values of a Prometheus label.
  # `allValue` is what "All" expands to; a regex there keeps queries that use
  # `=~"$var"` working, while leaving it unset makes "All" expand to the list of
  # values, which is what `group`'s `repeat` iterates over.
  labelVariable = {
    name,
    label ? name,
    title ? null,
    description ? null,
    matchers ? [],
    multiple ? false,
    all ? false,
    allValue ? null,
    default ? null,
    hidden ? false,
  }: {
    kind = "ListVariable";
    spec =
      {
        inherit name;
        display =
          {inherit hidden;}
          // prune {
            name = title;
            inherit description;
          };
        allowAllValue = all;
        allowMultiple = multiple;
        sort = "alphabetical-asc";
        plugin = {
          kind = "PrometheusLabelValuesVariable";
          spec =
            {labelName = label;}
            // lib.optionalAttrs (matchers != []) {inherit matchers;};
        };
      }
      // prune {
        customAllValue = allValue;
        defaultValue = default;
      };
  };
}

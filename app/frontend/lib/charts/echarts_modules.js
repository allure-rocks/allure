// The ECharts build Allure ships: the core with only the series, components
// and renderer the charts use. Named imports keep the bundle tree-shaken;
// this module is only ever loaded through `loadECharts()`.
import * as echarts from "echarts/core";
import { BarChart, LineChart, PieChart, RadarChart, ScatterChart } from "echarts/charts";
import {
  BrushComponent,
  DataZoomComponent,
  GraphicComponent,
  GridComponent,
  LegendComponent,
  MarkAreaComponent,
  MarkLineComponent,
  MarkPointComponent,
  RadarComponent,
  ToolboxComponent,
  TooltipComponent,
} from "echarts/components";
import { SVGRenderer } from "echarts/renderers";

echarts.use([
  LineChart,
  BarChart,
  ScatterChart,
  PieChart,
  RadarChart,
  RadarComponent,
  GridComponent,
  TooltipComponent,
  ToolboxComponent,
  BrushComponent,
  DataZoomComponent,
  MarkPointComponent,
  MarkLineComponent,
  MarkAreaComponent,
  GraphicComponent,
  LegendComponent,
  SVGRenderer,
]);

export default echarts;

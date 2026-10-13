/**
 * デザイントークンの期待値。**ここにだけ**置く。
 *
 * 値は決めた値をそのまま書く。`globals.css` から読み直さない — 読み直すと、
 * トークンの値を間違えても期待値が一緒に動き、テストが落ちない。
 */

export type Theme = "light" | "dark";
/** [r, g, b, a]。r・g・b は 0〜255、a は 0〜1。 */
export type Rgba = readonly [number, number, number, number];
export type ThemeColor = Readonly<Record<Theme, Rgba>>;

export function hex(value: string): Rgba {
  const h = value.replace("#", "");
  const n = (i: number) => parseInt(h.slice(i, i + 2), 16);
  const a = h.length === 8 ? n(6) / 255 : 1;
  return [n(0), n(2), n(4), a];
}

export const rgba = (r: number, g: number, b: number, a = 1): Rgba => [r, g, b, a];
const pair = (light: Rgba, dark: Rgba): ThemeColor => ({ light, dark });

export const TRANSPARENT: Rgba = [0, 0, 0, 0];
export const WHITE: Rgba = [255, 255, 255, 1];

/** 色 */
export const COLOR = {
  background: pair(hex("#f4f4f5"), hex("#111113")),
  card: pair(hex("#ffffff"), hex("#18181b")),
  surfaceRaised: pair(hex("#ffffff"), hex("#1f1f23")),
  sidebarSelected: pair(hex("#ffffff"), hex("#27272a")),
  rowHover: pair(hex("#fafafa"), rgba(255, 255, 255, 0.03)),
  foreground: pair(hex("#09090b"), hex("#fafafa")),
  foreground2: pair(hex("#3f3f46"), hex("#d4d4d8")),
  mutedForeground: pair(hex("#68686f"), hex("#a1a1aa")),
  dividerStrong: pair(rgba(9, 9, 11, 0.1), rgba(255, 255, 255, 0.1)),
  divider: pair(rgba(9, 9, 11, 0.08), rgba(255, 255, 255, 0.08)),
  dividerSubtle: pair(rgba(9, 9, 11, 0.05), rgba(255, 255, 255, 0.06)),
  controlBorder: pair(hex("#8a8a93"), hex("#71717a")),
  primary: pair(hex("#4f46e5"), hex("#5a53ee")),
  primaryEdge: pair(rgba(0, 0, 0, 0.18), rgba(255, 255, 255, 0.12)),
  link: pair(hex("#4338ca"), hex("#a5b4fc")),
  linkHover: pair(hex("#3730a3"), hex("#c7d2fe")),
  ring: pair(hex("#4f46e5"), hex("#818cf8")),
  filterActiveBg: pair(rgba(79, 70, 229, 0.06), rgba(99, 102, 241, 0.15)),
  filterActiveBorder: pair(hex("#6366f1"), hex("#818cf8")),
  filterActiveForeground: pair(hex("#3730a3"), hex("#c7d2fe")),
  neutralChipBg: pair(rgba(113, 113, 122, 0.1), rgba(161, 161, 170, 0.15)),
  warningForeground: pair(hex("#c2410c"), hex("#fb923c")),
} as const;

/** 状況のバッジ (面・文字と点) */
export const BADGE: Record<string, { bg: ThemeColor; fg: ThemeColor }> = {
  受注済: { bg: pair(rgba(113, 113, 122, 0.1), rgba(161, 161, 170, 0.15)), fg: pair(hex("#3f3f46"), hex("#e4e4e7")) },
  一部引当: { bg: pair(rgba(234, 179, 8, 0.15), rgba(234, 179, 8, 0.15)), fg: pair(hex("#854d0e"), hex("#fde047")) },
  引当済: { bg: pair(rgba(14, 165, 233, 0.12), rgba(14, 165, 233, 0.15)), fg: pair(hex("#0369a1"), hex("#7dd3fc")) },
  出荷指示済: { bg: pair(rgba(249, 115, 22, 0.12), rgba(249, 115, 22, 0.15)), fg: pair(hex("#9a3412"), hex("#fdba74")) },
  出荷済: { bg: pair(rgba(34, 197, 94, 0.12), rgba(34, 197, 94, 0.15)), fg: pair(hex("#166534"), hex("#86efac")) },
  キャンセル: { bg: pair(rgba(239, 68, 68, 0.1), rgba(239, 68, 68, 0.15)), fg: pair(hex("#b91c1c"), hex("#fca5a5")) },
};

/** かんばんの列見出しの下線 (状況の色相の 500 番。テーマで変わらない) */
export const STATUS_LINE: Record<string, Rgba> = {
  受注済: hex("#a1a1aa"),
  一部引当: hex("#eab308"),
  引当済: hex("#0ea5e9"),
  出荷指示済: hex("#f97316"),
  出荷済: hex("#22c55e"),
  キャンセル: hex("#ef4444"),
};

/** box-shadow の 1 層。長さは px。 */
export type ShadowLayer = {
  inset: boolean;
  x: number;
  y: number;
  blur: number;
  spread: number;
  color: Rgba;
};

const layer = (inset: boolean, x: number, y: number, blur: number, spread: number, color: Rgba): ShadowLayer => ({
  inset,
  x,
  y,
  blur,
  spread,
  color,
});

/** 影。色の部分だけがテーマで変わる */
export const SHADOW: Record<
  "panel" | "card" | "cardHover" | "control" | "primary" | "popup" | "filterActive",
  Record<Theme, ShadowLayer[]>
> = {
  panel: {
    light: [layer(false, 0, 1, 2, 0, hex("#0000000d")), layer(false, 0, 0, 0, 1, hex("#09090b0d"))],
    dark: [layer(false, 0, 1, 2, 0, hex("#00000066")), layer(false, 0, 0, 0, 1, hex("#ffffff0f"))],
  },
  card: {
    light: [layer(false, 0, 1, 2, 0, hex("#0000000d")), layer(false, 0, 0, 0, 1, hex("#09090b0f"))],
    dark: [layer(false, 0, 1, 2, 0, hex("#00000066")), layer(false, 0, 0, 0, 1, hex("#ffffff0f"))],
  },
  cardHover: {
    light: [layer(false, 0, 4, 12, -2, hex("#0000001a")), layer(false, 0, 0, 0, 1, hex("#09090b14"))],
    dark: [layer(false, 0, 4, 12, -2, hex("#00000080")), layer(false, 0, 0, 0, 1, hex("#ffffff1f"))],
  },
  control: {
    light: [layer(false, 0, 1, 2, 0, hex("#0000000d")), layer(true, 0, 0, 0, 1, COLOR.controlBorder.light)],
    dark: [layer(false, 0, 1, 2, 0, hex("#00000066")), layer(true, 0, 0, 0, 1, COLOR.controlBorder.dark)],
  },
  primary: {
    light: [
      layer(true, 0, 0, 0, 1, COLOR.primaryEdge.light),
      layer(true, 0, -2, 0, 0, hex("#0000001a")),
      layer(true, 0, 1, 0, 0, hex("#ffffff33")),
      layer(false, 0, 1, 2, 0, hex("#4338ca33")),
    ],
    dark: [
      layer(true, 0, 0, 0, 1, COLOR.primaryEdge.dark),
      layer(true, 0, -2, 0, 0, hex("#0000001a")),
      layer(true, 0, 1, 0, 0, hex("#ffffff33")),
      layer(false, 0, 1, 2, 0, hex("#00000066")),
    ],
  },
  popup: {
    light: [layer(false, 0, 8, 24, -4, hex("#0000001f")), layer(false, 0, 0, 0, 1, hex("#09090b14"))],
    dark: [layer(false, 0, 8, 24, -4, hex("#00000099")), layer(false, 0, 0, 0, 1, hex("#ffffff1f"))],
  },
  /** 値を選んでいる絞り込みボタン: --filter-active-border の内側 1px の縁取りだけ (見本 orders.html の .fbtn.set) */
  filterActive: {
    light: [layer(true, 0, 0, 0, 1, COLOR.filterActiveBorder.light)],
    dark: [layer(true, 0, 0, 0, 1, COLOR.filterActiveBorder.dark)],
  },
};

/** 角丸・文字・余白 (px) */
export const SIZE = {
  radiusBadge: 6,
  radiusControl: 8,
  radiusPanel: 12,
  panelPaddingTop: 28,
  panelPaddingLeft: 40,
  sidebarWidth: 248,
  sidebarItemHeight: 36,
  controlHeight: 36,
  h1FontSize: 22,
  h1LineHeight: 28.6,
  tableHeadFontSize: 13,
  badgeFontSize: 13,
  tableRowHeight: 52,
  radiusCard: 10,
  cardPadding: 14,
  kpiValueFontSize: 32,
  /** −0.02em × 32px */
  kpiValueLetterSpacing: -0.64,
  kanbanHeadLine: 2,
  alertRowHeight: 48,
  dashboardGap: 32,
  /** 一覧の画面内の間隔 (見出しとタブの並びの間など) */
  listGap: 20,
  /** 選択中のタブの下線 */
  tabUnderline: 2,
  /** かんばんのカードのボタン (二次ボタンの小) */
  cardButtonHeight: 30,
  cardButtonPaddingX: 12,
  cardButtonFontSize: 13,
  /** 絞り込みボタン (角丸・文字・余白) */
  filterHeight: 32,
  filterFontSize: 13,
  /** メニューの高さの上限 (1280×720 では利用できる高さより小さい) */
  menuMaxHeight: 320,
} as const;

/** 色の比べ方: r・g・b は一致、不透明度は ±0.01 */
export const ALPHA_TOLERANCE = 0.01;
/** 寸法の比べ方: ±0.5px */
export const PX_TOLERANCE = 0.5;

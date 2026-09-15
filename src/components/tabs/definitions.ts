export type BadgeValue = number | "dot" | null;

/** Shape options for image icon containers */
export type ImageIconShape = "circle" | "square";

/** Size behavior options for image scaling */
export type ImageIconSize = "cover" | "stretch" | "fit";

/** Ring configuration for selected image icons */
export interface ImageIconRing {
  /** Whether to show ring around the image */
  enabled: boolean;
  /** Width of the ring in pixels (default: 2.0) */
  width?: number;
}

/** Image icon configuration object */
export interface ImageIcon {
  /** Shape of the icon container */
  shape: ImageIconShape;
  /** Image scaling behavior */
  size: ImageIconSize;
  /** Image source - either base64 data URI or HTTP/HTTPS URL */
  image: string;
  /** Optional ring configuration for selected and unselected states */
  ring?: ImageIconRing;
}

/** Loading state for remote images */
export type ImageLoadingState = "loading" | "loaded" | "error";

/** Tab role — `search` uses the system search tab styling on iOS 26+. */
export type TabItemRole = "search";

export interface TabItem {
  /** Unique id you use in your router (e.g., 'home') */
  id: string;
  /** Title shown under the icon (optional if you want icon-only) */
  title?: string;
  /** SF Symbol name (e.g., 'house', 'sparkles') - compulsory fallback when imageIcon fails */
  systemIcon: string;
  /** Or provide an asset name bundled on iOS (selected/unselected are tinted by system) */
  image?: string;
  /** Optional enhanced image icon with shape, size, and remote/base64 support */
  imageIcon?: ImageIcon;
  /** Optional badge number or 'dot' */
  badge?: BadgeValue;
  /** Optional tab role — `search` for native search tab pill (iOS 26+). */
  role?: TabItemRole;
}

/** iOS 26+ tab bar minimize-on-scroll behavior. */
export type TabBarMinimizeBehavior = "never" | "onScrollDown" | "onScrollUp" | "automatic";

export interface TabsBarConfigureOptions {
  items: TabItem[];
  /** Which tab is selected initially */
  initialId?: string;
  /** Show immediately (default true) */
  visible?: boolean;
  /** Color for the selected tab icon (hex or RGBA format) */
  selectedIconColor?: string;
  /** Color for unselected tab icons (hex or RGBA format) */
  unselectedIconColor?: string;
  /** iOS 26+ minimize behavior (default `never` — web scroll forwarding not yet wired). */
  tabBarMinimizeBehavior?: TabBarMinimizeBehavior;
}

export interface SelectOptions {
  id: string;
}

export interface SetBadgeOptions {
  id: string;
  value: BadgeValue;
}

export interface SafeAreaInsets {
  top: number; bottom: number; left: number; right: number;
}

export interface BottomAccessoryOptions {
  /** Show the accessory (default true). Pass false to hide without clearing state. */
  visible?: boolean;
  title?: string;
  subtitle?: string;
  isPlaying?: boolean;
  animated?: boolean;
  /** Remote http(s), file://, or data URI for accessory artwork. */
  artworkUrl?: string;
}

export interface TabAccessoryEnvironment {
  /** `inline` when minimized tab bar shares a row with the accessory; `stacked` otherwise. */
  environment: "inline" | "stacked" | "unknown";
}

export interface TabBarMetrics {
  /** Distance from overlay bottom to bottom chrome top (accessory or bottom tab pill). 0 if the tab bar is at the top. */
  tabBarTopOffset: number;
  /** Height of the bottom accessory when visible (0 otherwise). */
  accessoryHeight: number;
  /** `top` on iPad regular width; `bottom` for the floating pill. */
  placement: "top" | "bottom";
  /** Extra padding below the status bar so web headers sit under a top-placed tab bar. */
  tabBarTopInset: number;
}

export interface TabsBarPlugin {
  configure(options: TabsBarConfigureOptions): Promise<void>;
  show(): Promise<void>;
  hide(): Promise<void>;
  select(options: SelectOptions): Promise<void>;
  setBadge(options: SetBadgeOptions): Promise<void>;
  getSafeAreaInsets(): Promise<SafeAreaInsets>;
  /** iOS 26+ mini-player slot above the tab bar (Apple Music pattern). */
  setBottomAccessory(options: BottomAccessoryOptions): Promise<void>;
  clearBottomAccessory(options?: { animated?: boolean }): Promise<void>;
  getTabAccessoryEnvironment(): Promise<TabAccessoryEnvironment>;
  getTabBarMetrics(): Promise<TabBarMetrics>;

  /** Fires when user taps a tab */
  addListener(
    eventName: "selected",
    listenerFunc: (ev: { id: string }) => void
  ): Promise<{ remove: () => void }>;
  /** Fires when user taps play/pause on the bottom accessory. */
  addListener(
    eventName: "accessoryPlayPause",
    listenerFunc: () => void
  ): Promise<{ remove: () => void }>;
  /** Fires when user taps the bottom accessory body (open full player). */
  addListener(
    eventName: "accessoryTapped",
    listenerFunc: () => void
  ): Promise<{ remove: () => void }>;
  /** Fires when accessory layout switches inline vs stacked. */
  addListener(
    eventName: "accessoryEnvironmentChanged",
    listenerFunc: (ev: TabAccessoryEnvironment) => void
  ): Promise<{ remove: () => void }>;
}
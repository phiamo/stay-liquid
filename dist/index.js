// src/components/tabs/index.ts
import { registerPlugin } from "@capacitor/core";
var TabsBar = registerPlugin("TabsBar", {
  web: () => import("./web-7ENEOAVK.js").then((m) => new m.TabsBarWeb())
});
export {
  TabsBar
};

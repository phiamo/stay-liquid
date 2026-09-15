// src/components/tabs/index.ts
import { registerPlugin } from "@capacitor/core";
var TabsBar = registerPlugin("TabsBar", {
  web: () => import("./web-C6H22WOF.js").then((m) => new m.TabsBarWeb())
});
export {
  TabsBar
};

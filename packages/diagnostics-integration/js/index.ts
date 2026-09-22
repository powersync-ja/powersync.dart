import { App, createApp, h } from "vue";
import {
  DiagnosticsPanel,
  provideDiagnostics,
} from "@powersync/diagnostics-ui";
import type { SdkIntegration } from "@powersync/diagnostics-core";

export function appFactory(integration: Promise<SdkIntegration>): App {
  return createApp({
    setup() {
      provideDiagnostics(integration);
      return () => h("div", { style: "height: 100vh" }, [h(DiagnosticsPanel)]);
    },
  });
}

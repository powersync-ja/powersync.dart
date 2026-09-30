import { App, createApp, h, Ref } from "vue";
import {
  DiagnosticsPanel,
  DiagnosticsTheme,
  provideDiagnostics,
} from "@powersync/diagnostics-ui";
import type { SdkIntegration } from "@powersync/diagnostics-core";

export { ref } from "vue";

export function appFactory(
  integration: Promise<SdkIntegration>,
  theme: Ref<DiagnosticsTheme>,
): App {
  return createApp({
    setup() {
      provideDiagnostics(integration, { theme });
      return () => h("div", { style: "height: 100vh" }, [h(DiagnosticsPanel)]);
    },
  });
}

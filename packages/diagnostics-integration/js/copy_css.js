// Copies styles from the diagnostics ui bundle to web/js-dist, which are referenced by index.html
import { copyFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const source = fileURLToPath(
  import.meta.resolve("@powersync/diagnostics-ui/style.css"),
);
const destination = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "web",
  "js-dist",
  "style.css",
);

await copyFile(source, destination);

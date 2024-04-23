import { type Config, defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "abi/generated.ts",
  contracts: [],
  plugins: [
    foundry({
      project: "./",
    }),
  ],
}) as Config;
